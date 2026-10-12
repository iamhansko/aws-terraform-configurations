data "aws_region" "current" {}

# The addresses CloudFront's edge locations make origin requests from.
#
# Looked up by name, where the _monolithic template carried a mapping of hardcoded prefix
# list IDs keyed by region. Two things were wrong with that: the IDs are per-region values
# AWS can change, and a region missing from the table failed with an error about a map key
# rather than about a region.
data "aws_ec2_managed_prefix_list" "cloudfront_origin_facing" {
  name = var.cloudfront_prefix_list_name
}

# The managed origin request policy, by name rather than by the UUID the console shows.
data "aws_cloudfront_origin_request_policy" "all_viewer" {
  name = var.cloudfront_origin_request_policy_name
}

module "network" {
  source = "./modules/network"

  vpc_cidr_block           = var.vpc_cidr_block
  vpc_name                 = "${var.project_name}-vpc"
  internet_gateway_name    = "${var.project_name}-igw"
  public_subnet_name       = "${var.project_name}-public"
  private_subnet_name      = "${var.project_name}-private"
  public_route_table_name  = "${var.project_name}-public-rt"
  private_route_table_name = "${var.project_name}-private-rt"
  nat_gateway_name         = "${var.project_name}-natgw"
  # The AWS Load Balancer Controller discovers subnets by tag, not by configuration, and a
  # scheme that does not match the tags fails with "couldn't auto-discover subnets". The
  # _monolithic template tagged nothing, so the internet-facing Ingress it applied had
  # nothing to find (rules.md G-1).
  public_subnet_tags = {
    "kubernetes.io/role/elb" = "1"
  }
  private_subnet_tags = {
    "kubernetes.io/role/internal-elb" = "1"
  }
}

module "key_pair" {
  source = "./modules/key_pair"

  key_name = "${var.project_name}-key"

  # Nothing here reads a network output, but the root orders every module after the network
  # so the whole VPC - NAT gateways and route tables included - is finished before anything
  # starts in it (rules.md D-3).
  depends_on = [module.network]
}

module "eks_cluster" {
  source = "./modules/eks_cluster"

  name                   = var.cluster_name
  kubernetes_version     = var.kubernetes_version
  subnet_ids             = concat(module.network.public_subnet_ids, module.network.private_subnet_ids)
  endpoint_public_access = var.endpoint_public_access
  public_access_cidrs    = var.public_access_cidrs

  depends_on = [module.network]
}

# vpc-cni and kube-proxy are DaemonSets, so they reach ACTIVE with zero nodes. They come
# before the node group because a node cannot join Ready without them, and with
# bootstrap_self_managed_addons = false nothing installs them otherwise (rules.md C-4).
module "eks_vpc_cni_addon" {
  source = "./modules/eks_vpc_cni_addon"

  cluster_name = module.eks_cluster.cluster_name

  depends_on = [module.network, module.eks_cluster]
}

module "eks_kube_proxy_addon" {
  source = "./modules/eks_kube_proxy_addon"

  cluster_name = module.eks_cluster.cluster_name

  depends_on = [module.network, module.eks_cluster]
}

# The node group that runs the cluster's own controllers. Karpenter, the load balancer
# controller, the device plugin and the KubeRay operator all land here, which is not an
# accident: a controller that provisions nodes cannot depend on the nodes it provisions,
# and the GPU pools are tainted anyway.
module "eks_node_group" {
  source = "./modules/eks_node_group"

  cluster_name    = module.eks_cluster.cluster_name
  node_group_name = var.core_node_group_name
  instance_types  = var.core_node_instance_types
  labels          = var.core_node_labels
  desired_size    = var.core_node_desired_size
  min_size        = var.core_node_min_size
  max_size        = var.core_node_max_size
  key_name        = module.key_pair.key_name
  subnet_ids      = module.network.private_subnet_ids

  depends_on = [module.network, module.eks_vpc_cni_addon, module.eks_kube_proxy_addon]
}

# coredns is a Deployment, so unlike the DaemonSets it needs schedulable node capacity to
# leave DEGRADED and become ACTIVE (rules.md C-4).
module "eks_coredns_addon" {
  source = "./modules/eks_coredns_addon"

  cluster_name          = module.eks_cluster.cluster_name
  coredns_replica_count = var.coredns_replica_count

  depends_on = [
  module.network, module.eks_node_group]
}

# Karpenter's controller, its IAM role and the node role its instances assume. The pools
# are separate modules below.
#
# The _monolithic template installed this by writing a shell script onto the bastion from
# user data and running it, so the release existed in no state file - and the script
# exported KARPENTER_VERSION, K8S_VERSION, AWS_ACCOUNT_ID and a TEMPOUT it never used
# (rules.md E-1).
module "karpenter" {
  source = "./modules/karpenter"

  cluster_name      = module.eks_cluster.cluster_name
  oidc_provider_arn = module.eks_cluster.oidc_provider_arn
  oidc_issuer_host  = module.eks_cluster.oidc_issuer_host
  chart_version     = var.karpenter_chart_version

  # The controller runs on the core node group, and its pods need DNS to reach the EKS and
  # EC2 APIs. Neither is expressed by a value reference (rules.md D-2).
  depends_on = [module.network, module.eks_node_group, module.eks_coredns_addon]
}

# One module per pool. for_each over a map whose keys are literals in this configuration,
# so they are known at plan time and safe as resource addresses - the values inside
# (subnet IDs, the security group ID, the node role name) are what come from other modules
# (rules.md B-7/B-8).
module "karpenter_node_pool" {
  source   = "./modules/karpenter_node_pool"
  for_each = var.karpenter_node_pools

  name               = each.key
  node_iam_role_name = module.karpenter.node_role_name
  # Private subnets only. Karpenter nodes pull multi-gigabyte model images through the NAT
  # gateways, and nothing outside the VPC has a reason to reach them.
  subnet_ids         = module.network.private_subnet_ids
  security_group_ids = [module.eks_cluster.cluster_security_group_id]

  instance_families     = each.value.instance_families
  instance_sizes        = each.value.instance_sizes
  capacity_types        = each.value.capacity_types
  node_labels           = each.value.node_labels
  taints                = each.value.taints
  ami_alias             = each.value.ami_alias
  block_device_mappings = each.value.block_device_mappings
  instance_store_policy = each.value.instance_store_policy
  cpu_limit             = each.value.cpu_limit
  memory_limit          = each.value.memory_limit

  # The CRDs these instantiate ship with the Karpenter chart, so the release has to be
  # installed first. Stated on the module block rather than injected into the module as a
  # dependency variable, so the module never learns a Helm release exists
  # (rules.md D-2/D-4).
  depends_on = [
  module.network, module.karpenter]
}

# What makes a GPU node's GPUs schedulable. Without it the g5 and g6 nodes join, report
# Ready, and advertise no nvidia.com/gpu - so the Ray workers stay Pending on a cluster
# that physically has the hardware.
#
# A Helm release rather than the plugin's static DaemonSet manifest applied from a GitHub
# raw URL, which is what the _monolithic template did at a pinned v0.17.1 - neither
# versioned by Helm nor upgradeable (rules.md E-1).
module "nvidia_device_plugin" {
  source = "./modules/nvidia_device_plugin"

  chart_version = var.nvidia_device_plugin_chart_version
  # No time slicing. Each Serve replica reserves a whole GPU, so splitting one device
  # between replicas would only make them contend for memory (rules.md B-4).
  time_slicing_replicas = null

  depends_on = [
  module.network, module.eks_node_group, module.eks_coredns_addon]
}

# The controller that turns the Ray Serve Ingress into an ALB. Its IRSA role and its Helm
# release stay in one module because they reference each other (rules.md C-2).
module "aws_load_balancer_controller" {
  source = "./modules/aws_load_balancer_controller"

  cluster_name                  = module.eks_cluster.cluster_name
  vpc_id                        = module.network.vpc_id
  aws_region                    = data.aws_region.current.region
  oidc_provider_arn             = module.eks_cluster.oidc_provider_arn
  oidc_issuer_host              = module.eks_cluster.oidc_issuer_host
  chart_version                 = var.load_balancer_controller_chart_version
  enable_backend_security_group = var.enable_backend_security_group
  # Off, because no Service in this project is of type LoadBalancer - the ALB comes from
  # the Ray Serve Ingress, and every Service here is ClusterIP. Left on, the webhook it
  # installs gates every Service creation in the cluster behind a controller pod being
  # Ready, and module.karpenter and module.kuberay_operator share no ordering with this
  # module, so their Services land in exactly that window - which is how both releases
  # failed with "failed calling webhook mservice.elbv2.k8s.aws". Ordering them after this
  # module instead would only cover the apply, not a later controller rollout
  # (rules.md G-4).
  enable_service_mutator_webhook = var.enable_service_mutator_webhook

  depends_on = [module.network, module.eks_node_group, module.eks_coredns_addon]
}

locals {
  # Derived rather than a second variable, because the two values are only meaningful together
  # (rules.md B-1). Without the 0.0.0.0/0 rule an internet-facing ALB admits nobody: the bastion
  # reaches it through the internet gateway with its public address as the source, and a security
  # group reference matches private addresses only. Internal, the same request stays on private
  # addresses and the frontend group's bastion rule applies.
  alb_scheme = var.alb_allow_inbound_from_anywhere ? "internet-facing" : "internal"
}

# The ALB's frontend security group, created here rather than left to the controller so
# its rules are reviewable in the plan (rules.md G-1).
#
# The _monolithic template declared this group with no rules at all and then named it in
# the Ingress annotation alongside the cluster security group - so the ALB had a listener
# on port 80 and a frontend group that admitted nothing.
module "alb_security_group" {
  source = "./modules/load_balancer_security_group"

  vpc_id      = module.network.vpc_id
  name        = var.alb_security_group_name
  description = "Frontend security group for the ALB the controller builds from the Ray Serve Ingress"
  # One port, and it is the Serve port - the same value the RayService container exposes,
  # the Ingress backend names and the listen-ports annotation below makes the listener, so
  # none of them can disagree (rules.md B-5).
  ports = {
    serve = var.serve_port
  }
  allow_inbound_from_anywhere = var.alb_allow_inbound_from_anywhere
  # The bastion, which is where the endpoint is called from while the ALB is internal. A map
  # with a literal key because the ID is another module's output, unknown until apply
  # (rules.md B-8). The cluster security group both of them carry would admit this too, but
  # through a self-referencing rule nobody reviews as the way in - this group is the one whose
  # rules are meant to say who can reach the ALB.
  ingress_source_security_groups = {
    vscode_ec2 = module.vscode_ec2.security_group_id
  }

  depends_on = [module.network]
}

# The path from the ALB to the pods, which nothing else creates. With the shared backend
# security group off, the controller does not write a reduced set of pod-side rules - it
# leaves the networking spec out of the TargetGroupBinding altogether, so not one rule is
# created and every target reports unhealthy while the ALB itself looks fine
# (rules.md G-2).
#
# It modifies the cluster security group, which no module here owns outright, so it belongs
# in the root (rules.md C-1). target-type ip sends traffic to the Ray head pod's container
# port, and pods carry the cluster security group.
resource "aws_vpc_security_group_ingress_rule" "load_balancer_to_pods" {
  security_group_id            = module.eks_cluster.cluster_security_group_id
  description                  = "Ray Serve port from the ALB frontend security group"
  ip_protocol                  = "tcp"
  from_port                    = var.serve_port
  to_port                      = var.serve_port
  referenced_security_group_id = module.alb_security_group.security_group_id
}

# The KubeRay operator, which is what turns a RayService object into a Ray cluster and a
# Serve application.
module "kuberay_operator" {
  source = "./modules/kuberay_operator"

  chart_version = var.kuberay_chart_version

  depends_on = [
  module.network, module.eks_node_group, module.eks_coredns_addon]
}

# The workload: the RayService, its namespace, and the Ingress in front of the Serve HTTP
# port.
#
# The _monolithic template produced all three by echoing a 140-line YAML document out of a
# shell script an SSM Association ran, with two security group IDs substituted into an
# annotation string (rules.md E-1/E-3).
module "ray_service_workload" {
  source = "./modules/ray_service_workload"

  name        = var.ray_service_name
  namespace   = var.ray_service_namespace
  image       = var.ray_image
  ray_version = var.ray_version
  model_id    = var.model_id
  serve_port  = var.serve_port

  serve_min_replicas  = var.serve_min_replicas
  serve_max_replicas  = var.serve_max_replicas
  worker_min_replicas = var.serve_min_replicas
  worker_max_replicas = var.serve_max_replicas

  # Selectors and tolerations taken from the pools rather than restated as literal maps. A
  # selector that matches no pool leaves the pod Pending with the cluster apparently
  # healthy, and a toleration that does not match the pool's taint does the same
  # (rules.md B-5).
  head_node_selector   = module.karpenter_node_pool[var.head_node_pool].node_labels
  worker_node_selector = module.karpenter_node_pool[var.worker_node_pool].node_labels
  worker_node_taints   = module.karpenter_node_pool[var.worker_node_pool].taints

  ingress_annotations = {
    # internal unless the frontend group admits 0.0.0.0/0 - see local.alb_scheme. An
    # internal ALB is placed in the private subnets, which carry the internal-elb tag the
    # controller discovers them by (rules.md G-1).
    "alb.ingress.kubernetes.io/scheme"      = local.alb_scheme
    "alb.ingress.kubernetes.io/target-type" = "ip"
    # The listener on the Serve port, which is the port the frontend group opens. Without
    # this annotation the controller's default listener is HTTP:80 - a port the group never
    # opened - so the endpoint answered on neither port, in this configuration and in the
    # _monolithic template alike.
    "alb.ingress.kubernetes.io/listen-ports" = jsonencode([{ HTTP = var.serve_port }])
    # The target group's health check, which otherwise defaults to GET / expecting 200. The
    # Serve application routes /imagine and nothing else, so / answers 404 - from FastAPI once
    # the application is deployed, from the Serve proxy itself before that - and the head pod
    # stayed unhealthy in every state, a loaded model included. Nothing in plan or apply
    # shows it; describe-target-health reports Target.ResponseCodeMismatch [404].
    #
    # /-/healthz is answered by the Serve proxy rather than by the application: 200 once the
    # proxy holds a route table from the Serve controller, 503 while it has none or is
    # draining. It is the same endpoint KubeRay probes on this port to decide whether a pod's
    # proxy can take traffic.
    "alb.ingress.kubernetes.io/healthcheck-path" = "/-/healthz"
    # Both groups, as the _monolithic template's annotation had them: the frontend group
    # that admits the callers - the bastion, and the internet only when
    # alb_allow_inbound_from_anywhere is true - and the cluster group the pods carry. Naming
    # them here is what keeps the controller from replacing them.
    "alb.ingress.kubernetes.io/security-groups" = join(",", [
      module.alb_security_group.security_group_id,
      module.eks_cluster.cluster_security_group_id,
    ])
    # No load-balancer-name. The _monolithic template pinned the ALB's name to "serve",
    # which stops this project from being deployed twice in one account and turns a name
    # collision into an error the controller reports rather than anything about this
    # configuration (rules.md G-3 makes the same argument for a pre-created load
    # balancer's name).
  }

  # The operator has to be running before a RayService means anything, the controller
  # before the Ingress gets an address, and the device plugin before a worker pod can be
  # scheduled onto a GPU node. The pools have to exist before Karpenter has anywhere to
  # put those pods.
  #
  # Ordering the module after them is also what makes `terraform destroy` remove these
  # manifests while the operator and the controller are still alive - without it, destroy
  # can strand a RayService whose deletion waits on a controller that is already gone
  # (rules.md D-4).
  depends_on = [
    module.network,
    module.kuberay_operator,
    module.aws_load_balancer_controller,
    module.nvidia_device_plugin,
    module.karpenter_node_pool,
  ]
}

module "vscode_ec2" {
  source = "./modules/vscode_ec2"

  name                = "${var.project_name}-bastion"
  vpc_id              = module.network.vpc_id
  subnet_id           = module.network.public_subnet_a_id
  key_name            = module.key_pair.key_name
  instance_type       = var.bastion_instance_type
  code_server_version = var.code_server_version
  security_group_name = "${var.project_name}-bastion-sg"
  # False, as the _monolithic template had it: the only inbound rule is the CloudFront
  # origin-facing prefix list below, so the IDE is reached through the distribution - or
  # through the SSM port forward in the outputs, which needs no inbound rule at all.
  allow_inbound_from_anywhere = var.allow_bastion_inbound_from_anywhere
  ingress_prefix_list_ids     = [data.aws_ec2_managed_prefix_list.cloudfront_origin_facing.id]
  marker_file_path            = var.marker_file_path
  # Carrying the cluster security group is what lets kubectl on this instance reach the API
  # server without leaving the VPC. The module is handed an ID list and never learns what it
  # belongs to (rules.md B-6).
  extra_security_group_ids = [module.eks_cluster.cluster_security_group_id]
  # An EKS cluster and this instance share a root module, so this instance is the workbench
  # for that cluster and carries all five tools (rules.md H-1).
  #
  # None of them creates anything here. The _monolithic template used this same script to
  # install Karpenter and had an SSM Association install the load balancer controller, the
  # device plugin, the KubeRay operator, three Karpenter pools and the RayService; all of
  # those are provider resources now (rules.md E-1). What is left is what a person needs to
  # watch a GPU node being provisioned.
  additional_user_data = <<-EOT
    dnf install -yq docker
    systemctl enable --now docker
    usermod -aG docker ec2-user
    # code-server is already running and predates the docker group, so its terminals would
    # not have it without a restart. The _monolithic template commented out the usermod and
    # opened /var/run/docker.sock to 666 instead, which grants the same access to every
    # process on the host.
    systemctl restart code-server
    sudo -Eu ec2-user bash << 'EOF'
    export HOME=/home/ec2-user
    cd /home/ec2-user
    mkdir -p /home/ec2-user/bin
    curl -sO https://s3.us-west-2.amazonaws.com/amazon-eks/${var.kubectl_download_version}/bin/linux/amd64/kubectl
    chmod +x kubectl
    mv kubectl /home/ec2-user/bin/kubectl
    export PATH=/home/ec2-user/bin:$PATH
    echo 'export PATH=/home/ec2-user/bin:$PATH' >> ~/.bashrc
    # Order matters: bash_completion has to be sourced before kubectl's own completion,
    # which is what defines __start_kubectl, and that function has to exist before complete
    # references it. The _monolithic template had the complete line before the source line,
    # so every login printed "function not found" (rules.md H-1).
    echo 'source /usr/share/bash-completion/bash_completion' >> ~/.bashrc
    echo 'source <(kubectl completion bash)' >> ~/.bashrc
    echo 'alias k=kubectl' >> ~/.bashrc
    echo 'complete -o default -F __start_kubectl k' >> ~/.bashrc
    PLATFORM=$(uname -s)_amd64
    curl -sLO "https://github.com/eksctl-io/eksctl/releases/latest/download/eksctl_$PLATFORM.tar.gz"
    tar -xzf eksctl_$PLATFORM.tar.gz -C /tmp && rm eksctl_$PLATFORM.tar.gz
    sudo install -m 0755 /tmp/eksctl /usr/local/bin && rm /tmp/eksctl
    curl -fsSL -o get_helm.sh https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-4
    chmod 700 get_helm.sh
    ./get_helm.sh
    rm -f get_helm.sh
    aws configure set default.region ${data.aws_region.current.region}
    # Without this - and without the access entry below - kubectl is installed but every
    # command answers "You must be logged in to the server" (rules.md H-1).
    aws eks update-kubeconfig --region ${data.aws_region.current.region} --name ${module.eks_cluster.cluster_name}
    EOF
  EOT

  depends_on = [module.network]
}

# code-server in front of the bastion, so the IDE is served over HTTPS from an edge
# location rather than over plain HTTP from the instance's own address.
module "cloudfront_code_server" {
  source = "./modules/cloudfront_code_server"

  name               = var.project_name
  origin_domain_name = module.vscode_ec2.public_dns
  # The port from the module that configured code-server, so the origin and the listener
  # cannot disagree (rules.md B-5).
  origin_port              = module.vscode_ec2.code_server_port
  origin_request_policy_id = data.aws_cloudfront_origin_request_policy.all_viewer.id
  price_class              = var.cloudfront_price_class

  depends_on = [
  module.network, module.vscode_ec2]
}

# Granting the bastion's instance role cluster access joins two modules that know nothing
# about each other, so it belongs in the root (rules.md C-1).
resource "aws_eks_access_entry" "vscode_access_entry" {
  cluster_name  = module.eks_cluster.cluster_name
  principal_arn = module.vscode_ec2.iam_role_arn
  type          = "STANDARD"
}

resource "aws_eks_access_policy_association" "vscode_access_policy_association" {
  cluster_name  = module.eks_cluster.cluster_name
  principal_arn = module.vscode_ec2.iam_role_arn
  policy_arn    = "arn:aws:eks::aws:cluster-access-policy/AmazonEKSClusterAdminPolicy"
  access_scope {
    type = "cluster"
  }

  # EKS rejects a policy association for a principal with no access entry yet, and the two
  # resources share only literal argument values, so nothing orders them (rules.md D-1).
  # The _monolithic template had no ordering here at all.
  depends_on = [aws_eks_access_entry.vscode_access_entry]
}

# Not converted, deliberately: the cluster autoscaler.
#
# The _monolithic template created an IRSA role named cluster_autoscaler_role with an
# inline policy for autoscaling and EC2 describe calls - and then left the helm install
# that would have used it commented out, because Karpenter provisions the nodes here.
# The role was a permission granted for a workflow that does not exist, so it is dropped
# rather than carried forward. Adding the cluster autoscaler to a cluster Karpenter also
# manages would give two controllers the same job.

locals {
  # Every output this project exposes, defined once. outputs.tf projects these and the
  # README below renders them, so no value expression is written twice
  # (rules.md B-5/H-2). Adding an entry here is what makes an output possible, which is
  # what keeps the README from falling behind outputs.tf.
  outputs = {
    # Order 0 so it heads the README without renumbering every entry below it.
    vscode_port_forward_command = {
      order       = 0
      title       = "Connect to code-server through SSM"
      description = "Run this on your own machine rather than here: it needs the AWS CLI and the Session Manager plugin installed locally, and it keeps running until you stop it. While it runs, http://localhost:${module.vscode_ec2.code_server_port} is this IDE - the same code-server the CloudFront URL below serves, without going through the distribution. The tunnel rides the SSM agent's own outbound connection, so it needs no inbound rule on the bastion. Changing both port numbers reaches anything else listening on the bastion, such as the Ray dashboard port-forward below. SessionManagerPlugin is not found means the plugin is missing locally, not a permissions problem; TargetNotConnected means the agent on the bastion has not registered with Systems Manager"
      # --region because the instance lives where this configuration was applied, which need not be the
      # CLI's default region on the machine running the command.
      value = "aws ssm start-session --region ${data.aws_region.current.region} --target ${module.vscode_ec2.instance_id} --document-name AWS-StartPortForwardingSession --parameters '{\"portNumber\":[\"${module.vscode_ec2.code_server_port}\"],\"localPortNumber\":[\"${module.vscode_ec2.code_server_port}\"]}'"
    }
    vscode_url = {
      order       = 1
      title       = "code-server"
      description = "Open the IDE here. It is served through CloudFront over HTTPS; the instance's own port is only open to the CloudFront origin-facing prefix list"
      value       = module.cloudfront_code_server.url
    }
    cluster_name = {
      order       = 2
      title       = "EKS cluster name"
      description = "Name of the EKS cluster. Karpenter is given this as settings.clusterName, which is how its controller finds the cluster it provisions for"
      value       = module.eks_cluster.cluster_name
    }
    ray_dashboard_port_forward_command = {
      order       = 3
      title       = "Ray dashboard"
      description = "No Ingress routes to the dashboard, so it is reached by port-forward from the IDE terminal and then opened on localhost:8265. This is where a replica stuck loading the model is visible"
      value       = "kubectl -n ${module.ray_service_workload.namespace} port-forward service/${module.ray_service_workload.head_service_name} 8265:8265"
    }
    node_pools_command = {
      order       = 4
      title       = "1. The Karpenter pools exist"
      description = "Three pools: one CPU pool for the Ray head and two GPU pools. A pool missing here means its EC2NodeClass was rejected - kubectl describe ec2nodeclass <name> says why"
      value       = "kubectl get nodepool,ec2nodeclass"
    }
    nodes_command = {
      order       = 5
      title       = "2. Watch Karpenter provision a GPU node"
      description = "Starts with the core node group's nodes only. A g5 node appears once the Ray worker pod is pending, which takes a few minutes - Bottlerocket boots, then the several-gigabyte image pulls"
      value       = "kubectl get nodes -L nodegroup,type,karpenter.sh/capacity-type -o wide"
    }
    gpu_capacity_command = {
      order       = 6
      title       = "3. The GPUs are advertised"
      description = "The device plugin is what turns a GPU node into schedulable nvidia.com/gpu capacity. A zero here with a g5 node present means the plugin is not running on it, and the Ray workers will stay Pending"
      value       = module.nvidia_device_plugin.advertised_gpu_command
    }
    ray_service_status_command = {
      order       = 7
      title       = "4. The Serve application is running"
      description = "RUNNING means the model is loaded and the endpoint answers. DEPLOY_FAILED with a healthy Ray cluster is a Serve config problem rather than an infrastructure one"
      value       = module.ray_service_workload.ray_service_status_command
    }
    ray_pods_command = {
      order       = 8
      title       = "5. The head and the workers"
      description = "The head should be on an x86-cpu node and every worker on a g5-gpu node. A head on a GPU node means its nodeSelector was not applied, which is expensive rather than broken"
      value       = module.ray_service_workload.ray_pods_command
    }
    ingress_command = {
      order       = 9
      title       = "6. Read the ALB address"
      description = "The load balancer is created by the controller, not by Terraform, so its address exists only in the cluster (rules.md G-1). An empty ADDRESS points at the controller log below. An internal ALB, which is the default, has a name starting with internal- and resolves to private addresses only the VPC can reach"
      value       = module.ray_service_workload.load_balancer_hostname_command
    }
    generate_image_command = {
      order       = 10
      title       = "7. Generate an image"
      description = "Run it from the IDE terminal and substitute the ALB address from the previous step. While the ALB is internal the call has to come from inside the VPC, and the frontend security group admits the bastion; output.png lands in the terminal's working directory, where the IDE's explorer opens it. The first request waits for the model to load; later ones are faster, and enough of them at once will make Serve ask for a second replica and Karpenter for a second GPU node"
      value       = "curl -s -o output.png 'http://<alb-address>:${var.serve_port}/imagine?prompt=a%20cat%20astronaut' && ls -l output.png"
    }
    controller_log_command = {
      order       = 11
      title       = "8. Read the load balancer controller log"
      description = "Where to look if the Ingress never gets an address. The backend security group message described in rules.md G-2 appears only here - the apply succeeds either way"
      value       = "kubectl -n ${module.aws_load_balancer_controller.namespace} logs deploy/aws-load-balancer-controller --tail 100"
    }
    karpenter_log_command = {
      order       = 12
      title       = "9. Read the Karpenter log"
      description = "Where an unschedulable pod is explained. \"no instance type satisfied\" usually means the pod's resource request exceeds every size the pool allows, or its selector matches a pool whose taints it does not tolerate"
      value       = "kubectl -n ${module.karpenter.namespace} logs deploy/${module.karpenter.release_name} --tail 100"
    }
    kuberay_operator_log_command = {
      order       = 13
      title       = "10. Read the KubeRay operator log"
      description = "Where a rejected RayService spec is explained, including a Serve config key the Ray version no longer accepts"
      value       = module.kuberay_operator.operator_log_command
    }
    update_kubeconfig_command = {
      order       = 14
      title       = "Re-point kubectl"
      description = "User data already ran this, so kubectl works out of the box. Re-run it if the kubeconfig is ever lost"
      value       = "aws eks update-kubeconfig --region ${data.aws_region.current.region} --name ${module.eks_cluster.cluster_name}"
    }
  }
  # Iterating local.outputs directly would order sections by key. Re-keying by the order
  # field and taking values() sorts by that instead - values() returns a map's values
  # ordered by key - so the README reads in the order the demo is run.
  readme_ordered = values({
    for key, entry in local.outputs : format("%02d-%s", entry.order, key) => entry
  })
  readme_body = join("\n", concat(
    ["# ${var.project_name}", ""],
    flatten([for entry in local.readme_ordered : [
      "## ${entry.title}", "", entry.description, "", "```", entry.value, "```", "",
    ]]),
  ))
}

# The work happens inside code-server in a browser, where "terraform output" does not
# exist, so every output above is also written to a README in the home directory the IDE
# opens (rules.md H-2). The _monolithic template wrote no README at all here.
resource "aws_ssm_association" "vscode_readme" {
  name                             = "AWS-RunShellScript"
  wait_for_success_timeout_seconds = var.readme_timeout_seconds
  targets {
    key    = "InstanceIds"
    values = [module.vscode_ec2.instance_id]
  }
  parameters = {
    # The until loop, not depends_on or wait_for_success_timeout_seconds, is what orders
    # this after the instance bootstrap, and the marker this command leaves behind is what
    # a later association would wait on (rules.md D-5). The marker path comes back out of
    # the module it was passed into, so it is defined in exactly one place
    # (rules.md B-5).
    #
    # SSM runs as root, hence the chown. The heredoc delimiter is quoted and deliberately
    # unlikely to appear in the body: Terraform has already substituted every value, so the
    # shell has no reason to touch a "$" or a backtick in the README - and the commands in
    # it contain both.
    commands = <<-EOT
      until [ -f ${module.vscode_ec2.marker_file_path}/userdata ]; do sleep 10; done
      cat > /home/ec2-user/README.md << 'TFREADME'
      ${local.readme_body}
      TFREADME
      chown ec2-user:ec2-user /home/ec2-user/README.md
      touch ${module.vscode_ec2.marker_file_path}/vscode_readme
      EOT
  }
}
