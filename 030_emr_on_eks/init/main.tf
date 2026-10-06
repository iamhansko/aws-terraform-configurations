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
  # No kubernetes.io/role tags. Nothing in this variant asks for a load balancer - it is the
  # base layer the Spark variant builds on, and the only thing reaching into the cluster is the
  # workbench. Tagging subnets for a controller that is not installed would be a claim the
  # configuration does not back up (rules.md G-1 covers the case where Terraform has to write
  # them).
  public_subnet_tags  = {}
  private_subnet_tags = {}
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

# The node group that runs the cluster's own controllers. Karpenter and the device plugin land
# here, which is not an accident: a controller that provisions nodes cannot depend on the nodes
# it provisions, and the GPU pools are tainted anyway.
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
# Ready, and advertise no nvidia.com/gpu - so a pod asking for a GPU stays Pending on a cluster
# that physically has the hardware.
#
# A Helm release rather than the plugin's static DaemonSet manifest applied from a GitHub
# raw URL, which is what the _monolithic template did at a pinned v0.17.1 - neither
# versioned by Helm nor upgradeable (rules.md E-1).
module "nvidia_device_plugin" {
  source = "./modules/nvidia_device_plugin"

  chart_version = var.nvidia_device_plugin_chart_version
  # No time slicing. Nothing in this variant asks for a fraction of a GPU, and splitting one
  # device between pods that each want all of it only makes them contend for memory
  # (rules.md B-4).
  time_slicing_replicas = null

  depends_on = [
  module.network, module.eks_node_group, module.eks_coredns_addon]
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
  # origin-facing prefix list below, so the IDE is reached through the distribution.
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
  # install Karpenter and had an SSM Association apply three Karpenter pools and the device
  # plugin; all of those are provider resources now (rules.md E-1). What is left is what a
  # person needs to watch a node being provisioned.
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
    variant_note = {
      order       = 3
      title       = "What this variant is"
      description = "The base layer: a cluster with Karpenter, three node pools and the GPU device plugin, and nothing on top of it. basic_spark_job is the same thing plus an EMR on EKS virtual cluster and a Spark job to run in it"
      value       = "see ../basic_spark_job for the EMR on EKS variant"
    }
    node_pools_command = {
      order       = 4
      title       = "1. The Karpenter pools exist"
      description = "Three pools: one CPU pool and two GPU pools. A pool missing here means its EC2NodeClass was rejected - kubectl describe ec2nodeclass <name> says why"
      value       = "kubectl get nodepool,ec2nodeclass"
    }
    nodes_command = {
      order       = 5
      title       = "2. Watch Karpenter provision a node"
      description = "Starts with the core node group's nodes only. Create a pod that selects one of the pools and a node appears for it - Bottlerocket boots, then the image pulls"
      value       = "kubectl get nodes -L nodegroup,type,karpenter.sh/capacity-type -o wide"
    }
    gpu_capacity_command = {
      order       = 6
      title       = "3. The GPUs are advertised"
      description = "Zero until a GPU node exists, which Karpenter provisions only when something asks for one. A zero with a g5 node present means the device plugin is not running on it"
      value       = module.nvidia_device_plugin.advertised_gpu_command
    }
    demo_pod_command = {
      order       = 7
      title       = "4. Ask the CPU pool for a node"
      description = "Selects the x86-cpu pool's labels, so Karpenter has to provision an m5 instance for it. Watch the previous command while this is Pending"
      value       = "kubectl run karpenter-demo --image=public.ecr.aws/nginx/nginx:1.29 --restart=Never --overrides='{\"spec\":{\"nodeSelector\":{\"nodegroup\":\"x86-cpu\",\"type\":\"karpenter\"}}}' && kubectl wait --for=condition=Ready pod/karpenter-demo --timeout=600s && kubectl get pod karpenter-demo -o wide"
    }
    demo_pod_cleanup_command = {
      order       = 8
      title       = "5. Remove it again"
      description = "Karpenter consolidates the node away once it is empty, after the pool's consolidateAfter window. Worth doing: an m5 left running is the bill this variant can quietly accumulate"
      value       = "kubectl delete pod karpenter-demo --ignore-not-found"
    }
    karpenter_log_command = {
      order       = 9
      title       = "6. Read the Karpenter log"
      description = "Where an unschedulable pod is explained. \"no instance type satisfied\" usually means the pod's resource request exceeds every size the pool allows, or its selector matches a pool whose taints it does not tolerate"
      value       = "kubectl -n ${module.karpenter.namespace} logs deploy/${module.karpenter.release_name} --tail 100"
    }
    update_kubeconfig_command = {
      order       = 10
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
