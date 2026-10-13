# Resolve the public IPv4 address of the machine running Terraform once at the root. The child security
# group modules are ordered after other modules, so putting this plan-time read inside them could defer it
# until apply; passing only the resulting CIDR also keeps the modules independent of the lookup service
# (rules.md B-6/D-6).
data "http" "my_ip" {
  url = var.my_ip_lookup_url

  lifecycle {
    postcondition {
      condition = (
        self.status_code == 200 &&
        can(regex("^[0-9]{1,3}(\\.[0-9]{1,3}){3}$", trimspace(self.response_body))) &&
        can(cidrhost("${trimspace(self.response_body)}/32", 0))
      )
      error_message = "my_ip_lookup_url must return HTTP 200 with one bare IPv4 address. Set it to a trusted HTTPS address-reflection endpoint reachable from the machine running Terraform."
    }
  }
}
locals {
  my_ip_cidr = "${trimspace(data.http.my_ip.response_body)}/32"
}

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
# controller, the device plugin and Kubeflow's whole control plane all land here, which is
# not an accident: a controller that provisions nodes cannot depend on the nodes it
# provisions, and the GPU pools are tainted anyway.
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

# The Pod Identity agent, which is how the EBS CSI driver below gets its credentials. A
# DaemonSet, so it needs no node capacity to become ACTIVE - but it has to exist before any
# pod tries to exchange a token (rules.md C-4).
module "eks_pod_identity_agent_addon" {
  source = "./modules/eks_pod_identity_agent_addon"

  cluster_name = module.eks_cluster.cluster_name

  depends_on = [module.network, module.eks_cluster]
}

# The EBS CSI driver, with its own IAM role.
#
# Not optional in this project: Kubeflow's install claims persistent volumes for its
# pipelines metadata store, MinIO artifact store and MySQL, and every notebook server a user
# creates claims another. Without a driver answering those claims they stay Pending, the
# pods never start, and the dashboard shows a Kubeflow that came up half way.
#
# The _monolithic template built an IRSA role for this; Pod Identity is used instead because
# its trust policy names no OIDC issuer, so nothing in the role has to be rebuilt when the
# cluster is replaced.
module "eks_ebs_csi_driver_addon" {
  source = "./modules/eks_ebs_csi_driver_addon"

  cluster_name = module.eks_cluster.cluster_name

  # The controller half of this addon is a Deployment, so it needs node capacity to leave
  # DEGRADED - and the Pod Identity agent has to be running before its credentials work
  # (rules.md C-4/D-2).
  depends_on = [
  module.network, module.eks_node_group, module.eks_pod_identity_agent_addon]
}
# The default gp3 StorageClass, without which the addon above provisions nothing.
#
# A fresh EKS cluster has no default StorageClass to fall back on: its only class is the built-in
# gp2, whose in-tree kubernetes.io/aws-ebs provisioner was removed in Kubernetes 1.23, and which on
# current versions carries no default annotation (measured at 1.33). Kubeflow's claims come from
# upstream kustomize manifests and name no storageClassName - checked in the pinned v1.11.0 tree:
# katib-mysql, minio-pvc, mysql-pv-claim and metadata-mysql declare only accessModes and a size.
# Unlike a Helm chart there is no value to override, so a default class is the only way to connect
# them to the driver.
#
# This one fails quietly, which is why it is worth stating. The kustomize apply succeeds and
# centraldashboard has no volume, so the install association finishes and reports success while
# Katib, the pipeline metadata database and the artifact store stay Pending indefinitely.
#
# The _monolithic template did create this class, with a kubectl apply from the bastion before it
# installed Kubeflow (rules.md E-1/E-2). Losing it was a conversion regression.
module "csi_storage_classes" {
  source = "./modules/csi_storage_classes"

  storage_class_name = var.storage_class_name
  workload_namespace = var.kubeflow_namespace

  # kubectl_manifest resources against the cluster's API server, so ordering the module after the
  # nodes is what makes terraform destroy remove them while there is still something to process the
  # deletion (rules.md D-4). After the addon too: the class names a provisioner, and a class whose
  # driver is not registered yet accepts claims and provisions none.
  depends_on = [
  module.network, module.eks_node_group, module.eks_ebs_csi_driver_addon]
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
# Ready, and advertise no nvidia.com/gpu - so a Kubeflow training job asking for a GPU
# stays Pending on a cluster that physically has the hardware.
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

# The AWS Load Balancer Controller. Its IRSA role and its Helm release stay in one module
# because they reference each other (rules.md C-2).
#
# Nothing in this project creates an Ingress, so the controller is installed and idle. It is
# here because the _monolithic template installed it, and because it is what an Ingress in
# front of Kubeflow's istio-ingressgateway would need.
module "aws_load_balancer_controller" {
  source = "./modules/aws_load_balancer_controller"

  cluster_name                  = module.eks_cluster.cluster_name
  vpc_id                        = module.network.vpc_id
  aws_region                    = data.aws_region.current.region
  oidc_provider_arn             = module.eks_cluster.oidc_provider_arn
  oidc_issuer_host              = module.eks_cluster.oidc_issuer_host
  chart_version                 = var.load_balancer_controller_chart_version
  enable_backend_security_group = var.enable_backend_security_group
  # No Service of type LoadBalancer relies on this mutator. Leaving it enabled makes its
  # failurePolicy: Fail webhook a cluster-wide gate while this release starts in parallel
  # with Karpenter and the Kubeflow install (rules.md G-4).
  enable_service_mutator_webhook = var.enable_service_mutator_webhook

  depends_on = [module.network, module.eks_node_group, module.eks_coredns_addon]
}

# The ALB's frontend security group, created here rather than left to the controller so
# its rules are reviewable in the plan (rules.md G-1).
#
# The _monolithic template declared this group with no rules at all and then named it in
# the Ingress annotation alongside the cluster security group - so the ALB had a listener
# on 8000 and a frontend group that admitted nothing.
module "alb_security_group" {
  source = "./modules/load_balancer_security_group"

  vpc_id      = module.network.vpc_id
  name        = var.alb_security_group_name
  description = "Frontend security group for an ALB placed in front of the Kubeflow gateway"
  # The _monolithic template declared this group with no rules at all and then never
  # referenced it: it opened nothing and protected nothing. Opening the two ports an
  # Ingress in front of the gateway would listen on at least makes it usable
  # (rules.md B-5 - one map, and whoever adds the Ingress uses the same one).
  ports                       = var.alb_ports
  allow_inbound_from_anywhere = var.alb_allow_inbound_from_anywhere
  my_ip_cidr                  = local.my_ip_cidr
  # Who the group admits with 0.0.0.0/0 off, so it does not go back to opening nothing: the
  # bastion, the way the IDE terminal would call an internal ALB. A map with a literal key
  # because the ID is another module's output, unknown until apply (rules.md B-8).
  ingress_source_security_groups = {
    vscode_ec2 = module.vscode_ec2.security_group_id
  }

  depends_on = [module.network]
}
# No load_balancer_to_pods rule here, unlike the other load balancer projects.
#
# That rule exists to open the path from an ALB's frontend security group to the pods behind
# it, because with the shared backend security group off the controller writes no pod-side
# rules at all (rules.md G-2). There is no ALB and no target here yet: Kubeflow's dashboard
# is a ClusterIP Service reached by port-forward. Whoever puts an Ingress in front of
# istio-ingressgateway has to add the rule for the port that Ingress targets, and
# 088_ai_rayserve_on_eks shows the shape.

module "vscode_ec2" {
  source = "./modules/vscode_ec2"

  name                = "${var.project_name}-bastion"
  vpc_id              = module.network.vpc_id
  subnet_id           = module.network.public_subnet_a_id
  key_name            = module.key_pair.key_name
  instance_type       = var.bastion_instance_type
  code_server_version = var.code_server_version
  security_group_name = "${var.project_name}-bastion-sg"
  # The CloudFront origin-facing prefix list is additive. False, the default, also admits the detected My IP
  # /32 directly; true replaces that selected source with 0.0.0.0/0. The SSM port-forward output remains an
  # alternative that needs no inbound rule.
  allow_inbound_from_anywhere = var.allow_bastion_inbound_from_anywhere
  my_ip_cidr                  = local.my_ip_cidr
  ingress_prefix_list_ids     = [data.aws_ec2_managed_prefix_list.cloudfront_origin_facing.id]
  marker_file_path            = var.marker_file_path
  # Carrying the cluster security group is what lets kubectl on this instance reach the API
  # server without leaving the VPC. The module is handed an ID list and never learns what it
  # belongs to (rules.md B-6).
  extra_security_group_ids = [module.eks_cluster.cluster_security_group_id]
  # An EKS cluster and this instance share a root module, so this instance is the workbench
  # for that cluster and carries all five tools (rules.md H-1).
  #
  # Here kubectl is not only for debugging: the Kubeflow install below runs through it, which
  # is the one exception this project makes to rules.md E-1 - see providers.tf. Everything
  # else the _monolithic template installed from this script (Karpenter) or from its SSM
  # Association (the load balancer controller, the device plugin, three Karpenter pools) is a
  # provider resource now.
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

# Kubeflow itself, installed by an SSM Association running kubectl on the bastion rather
# than by a provider. providers.tf explains at length why this one thing is not a provider
# resource and what that costs; the short version is that the install is a kustomize build
# of a git repository producing about a thousand objects, which no data source can render.
#
# The until loop, not depends_on, is what orders this after the instance bootstrap:
# wait_for_success_timeout_seconds does not reliably wait for the remote command to finish,
# so the step waits for the bootstrap marker and leaves its own (rules.md D-5).
resource "aws_ssm_association" "kubeflow" {
  name                             = "AWS-RunShellScript"
  wait_for_success_timeout_seconds = var.kubeflow_install_timeout_seconds
  targets {
    key    = "InstanceIds"
    values = [module.vscode_ec2.instance_id]
  }
  parameters = {
    commands = <<-EOT
      set -euo pipefail
      until [ -f ${module.vscode_ec2.marker_file_path}/userdata ]; do sleep 10; done
      sudo -Eu ec2-user bash << 'STEP'
      set -euo pipefail
      export HOME=/home/ec2-user
      export PATH=/home/ec2-user/bin:$PATH
      # A pinned tag, and a fresh clone every time this step re-runs. An association re-runs
      # whenever its parameters change, so an existing checkout at a different ref would be
      # reused silently - which is the one way this step could install a version nobody
      # asked for.
      rm -rf /home/ec2-user/kubeflow-manifests
      git clone --depth 1 --branch ${var.kubeflow_manifests_ref} ${var.kubeflow_manifests_repository} /home/ec2-user/kubeflow-manifests
      cd /home/ec2-user/kubeflow-manifests
      # The retry loop is not a workaround for flakiness: the bundle installs CRDs and the
      # custom resources that use them in one pass, so the first apply always fails on kinds
      # that do not exist yet and a later one succeeds. --server-side --force-conflicts is
      # what lets a later pass take ownership of fields an earlier one set.
      #
      # Bounded, unlike the _monolithic template's "while ! ...; do sleep 20; done": an
      # unbounded loop turns a permanent failure into a step that runs until the
      # association's own timeout and reports nothing about why.
      applied=0
      for attempt in $(seq 1 ${var.kubeflow_apply_attempts}); do
        echo "kustomize apply attempt $attempt of ${var.kubeflow_apply_attempts}"
        if kubectl kustomize ${var.kubeflow_kustomize_path} | kubectl apply --server-side --force-conflicts -f -; then
          applied=1
          break
        fi
        sleep ${var.kubeflow_apply_interval_seconds}
      done
      if [ "$applied" -ne 1 ]; then
        echo "kustomize apply did not converge in ${var.kubeflow_apply_attempts} attempts"
        kubectl -n ${var.kubeflow_namespace} get pods 2>&1 | tail -40 || true
        exit 1
      fi
      # Waits for the one Deployment the dashboard is useless without, so the step's success
      # means something more than "the objects were accepted".
      kubectl -n ${var.kubeflow_namespace} rollout status deployment/centraldashboard --timeout=900s
      STEP
      touch ${module.vscode_ec2.marker_file_path}/kubeflow
      EOT
  }

  # Kubeflow's pods need node capacity, DNS, and a CSI driver to answer their volume claims.
  # The access entry has to exist before kubectl on this instance works at all.
  depends_on = [
    module.eks_node_group,
    module.eks_coredns_addon,
    module.eks_ebs_csi_driver_addon,
    # A default StorageClass has to exist before these manifests are applied, or their claims
    # resolve to no class and bind to nothing. Nothing here reads that module's outputs, and a
    # value reference would not have ordered anything anyway: its outputs are passthroughs of its
    # own variables and are therefore known at plan time (rules.md B-5/D-2).
    module.csi_storage_classes,
    aws_eks_access_policy_association.vscode_access_policy_association,
  ]
}

locals {
  # Every output this project exposes, defined once. outputs.tf projects these and the README
  # below renders them, so no value expression is written twice (rules.md B-5/H-2). Adding an
  # entry here is what makes an output possible, which is what keeps the README from falling
  # behind outputs.tf.
  outputs = {
    # Order 0 so it heads the README without renumbering every entry below it.
    vscode_port_forward_command = {
      order       = 0
      title       = "Connect to code-server through SSM"
      description = "Run this on your own machine rather than here: it needs the AWS CLI and the Session Manager plugin installed locally, and it keeps running until you stop it. While it runs, http://localhost:${module.vscode_ec2.code_server_port} is this IDE - the same code-server the CloudFront URL below serves, without going through the distribution. The tunnel rides the SSM agent's own outbound connection, so it needs no inbound rule on the bastion. Changing both port numbers reaches anything else listening on the bastion, such as the Kubeflow dashboard port-forward below. SessionManagerPlugin is not found means the plugin is missing locally, not a permissions problem; TargetNotConnected means the agent on the bastion has not registered with Systems Manager"
      # --region because the instance lives where this configuration was applied, which need not be the
      # CLI's default region on the machine running the command.
      value = "aws ssm start-session --region ${data.aws_region.current.region} --target ${module.vscode_ec2.instance_id} --document-name AWS-StartPortForwardingSession --parameters '{\"portNumber\":[\"${module.vscode_ec2.code_server_port}\"],\"localPortNumber\":[\"${module.vscode_ec2.code_server_port}\"]}'"
    }
    vscode_url = {
      order       = 1
      title       = "code-server"
      description = "Open the IDE through this preferred CloudFront HTTPS URL. The instance port also admits the detected My IP /32 by default; allow_bastion_inbound_from_anywhere = true replaces that selected source with 0.0.0.0/0"
      value       = module.cloudfront_code_server.url
    }
    cluster_name = {
      order       = 2
      title       = "EKS cluster name"
      description = "Name of the EKS cluster. Karpenter is given this as settings.clusterName, which is how its controller finds the cluster it provisions for"
      value       = module.eks_cluster.cluster_name
    }
    kubeflow_version = {
      order       = 3
      title       = "Kubeflow version"
      description = "The git tag the manifests were built from. Pinned, unlike the _monolithic template's clone of the default branch - which left no record anywhere of what was installed"
      value       = var.kubeflow_manifests_ref
    }
    kubeflow_dashboard_port_forward_command = {
      order       = 4
      title       = "Kubeflow dashboard"
      description = "The gateway is a ClusterIP Service, so the dashboard is reached by port-forward from the IDE terminal and then opened on localhost:8080. There is no authentication in front of it in this install"
      value       = "kubectl -n ${var.kubeflow_gateway_namespace} port-forward svc/${var.kubeflow_gateway_service_name} 8080:80"
    }
    node_pools_command = {
      order       = 5
      title       = "1. The Karpenter pools exist"
      description = "Three pools: one CPU pool for Kubeflow's own workloads and two GPU pools for training jobs. A pool missing here means its EC2NodeClass was rejected - kubectl describe ec2nodeclass <name> says why"
      value       = "kubectl get nodepool,ec2nodeclass"
    }
    kubeflow_pods_command = {
      order       = 6
      title       = "2. Kubeflow's control plane is running"
      description = "A few dozen pods, all on the core node group. A pod stuck in Pending here is almost always a PersistentVolumeClaim with nothing to answer it, which points at the EBS CSI driver"
      value       = "kubectl -n ${var.kubeflow_namespace} get pods"
    }
    kubeflow_claims_command = {
      order       = 7
      title       = "3. The volume claims are Bound"
      description = "Kubeflow claims volumes for its pipelines metadata store, its artifact store and its database. Pending claims mean the EBS CSI driver is not answering them, and every dependent pod stays Pending behind that"
      value       = "kubectl -n ${var.kubeflow_namespace} get pvc"
    }
    gpu_capacity_command = {
      order       = 8
      title       = "4. The GPUs are advertised"
      description = "Zero until a GPU node exists, which Karpenter provisions only when something asks for one. A zero here with a g5 node present means the device plugin is not running on it, and a training job asking for a GPU will stay Pending"
      value       = module.nvidia_device_plugin.advertised_gpu_command
    }
    nodes_command = {
      order       = 9
      title       = "5. Watch Karpenter provision a node"
      description = "Starts with the core node group's nodes only. Create a notebook server with a GPU from the dashboard and a g5 node appears for it - Bottlerocket boots, then the image pulls"
      value       = "kubectl get nodes -L nodegroup,type,karpenter.sh/capacity-type -o wide"
    }
    karpenter_log_command = {
      order       = 10
      title       = "6. Read the Karpenter log"
      description = "Where an unschedulable pod is explained. \"no instance type satisfied\" usually means the pod's resource request exceeds every size the pool allows, or its selector matches a pool whose taints it does not tolerate"
      value       = "kubectl -n ${module.karpenter.namespace} logs deploy/${module.karpenter.release_name} --tail 100"
    }
    controller_log_command = {
      order       = 11
      title       = "7. Read the load balancer controller log"
      description = "The controller is installed and idle - this project creates no Ingress. This is where to look after adding one in front of the Kubeflow gateway"
      value       = "kubectl -n ${module.aws_load_balancer_controller.namespace} logs deploy/aws-load-balancer-controller --tail 100"
    }
    alb_security_group_id = {
      order       = 12
      title       = "ALB frontend security group"
      description = "Ready for an Ingress in front of the Kubeflow gateway. The _monolithic template created this group with no rules and never referenced it; here it opens its ports to the bastion's security group, and to 0.0.0.0/0 only when alb_allow_inbound_from_anywhere is true. So an Ingress using it with that left false should be scheme internal, and whoever adds it still has to open the node-side path (rules.md G-2)"
      value       = module.alb_security_group.security_group_id
    }
    storage_class_name = {
      order       = 13
      title       = "StorageClass"
      description = "The default class Kubeflow's volume claims resolve through. Its upstream manifests name no storageClassName and offer no value to override, so the default annotation on this class is the only thing connecting Katib, the pipeline metadata database and the artifact store to the EBS CSI driver"
      value       = module.csi_storage_classes.storage_class_name
    }
    storage_class_check_command = {
      order       = 14
      title       = "Verify the default StorageClass"
      description = "Exactly one line should read (default), and it should be the gp3 one with provisioner ebs.csi.aws.com. The gp2 line is EKS's own and its kubernetes.io/aws-ebs provisioner has provisioned nothing since Kubernetes 1.23"
      value       = module.csi_storage_classes.storage_class_check_command
    }
    pending_claims_command = {
      order       = 15
      title       = "Check Kubeflow's volumes bound"
      description = "Worth running even though the install reported success. The dashboard has no volume so it comes up either way, and a claim Pending with an empty STORAGECLASS column means Katib and the pipeline store are silently dead"
      value       = module.csi_storage_classes.pending_claims_command
    }
    update_kubeconfig_command = {
      order       = 16
      title       = "Re-point kubectl"
      description = "User data already ran this, so kubectl works out of the box. Re-run it if the kubeconfig is ever lost"
      value       = "aws eks update-kubeconfig --region ${data.aws_region.current.region} --name ${module.eks_cluster.cluster_name}"
    }
  }
  # Iterating local.outputs directly would order sections by key. Re-keying by the order
  # field and taking values() sorts by that instead - values() returns a map's values ordered
  # by key - so the README reads in the order the demo is run.
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

# The work happens inside code-server in a browser, where "terraform output" does not exist,
# so every output above is also written to a README in the home directory the IDE opens
# (rules.md H-2). The _monolithic template wrote no README at all here.
resource "aws_ssm_association" "vscode_readme" {
  name                             = "AWS-RunShellScript"
  wait_for_success_timeout_seconds = var.readme_timeout_seconds
  targets {
    key    = "InstanceIds"
    values = [module.vscode_ec2.instance_id]
  }
  parameters = {
    # Waits on the Kubeflow step's marker rather than on the bootstrap marker, so the README
    # is written after the last thing it describes exists (rules.md D-5).
    #
    # SSM runs as root, hence the chown. The heredoc delimiter is quoted and deliberately
    # unlikely to appear in the body: Terraform has already substituted every value, so the
    # shell has no reason to touch a "$" or a backtick in the README.
    commands = <<-EOT
      until [ -f ${module.vscode_ec2.marker_file_path}/kubeflow ]; do sleep 10; done
      cat > /home/ec2-user/README.md << 'TFREADME'
      ${local.readme_body}
      TFREADME
      chown ec2-user:ec2-user /home/ec2-user/README.md
      touch ${module.vscode_ec2.marker_file_path}/vscode_readme
      EOT
  }

  depends_on = [aws_ssm_association.kubeflow]
}
