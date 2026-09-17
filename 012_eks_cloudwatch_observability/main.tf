data "aws_region" "current" {}
module "network" {
  source = "./modules/network"

  vpc_cidr_block           = var.vpc_cidr_block
  vpc_name                 = "${var.prefix}-vpc"
  internet_gateway_name    = "${var.prefix}-igw"
  public_subnet_name       = "${var.prefix}-public"
  private_subnet_name      = "${var.prefix}-private"
  public_route_table_name  = "${var.prefix}-public-rt"
  private_route_table_name = "${var.prefix}-private-rt"
  nat_gateway_name         = "${var.prefix}-natgw"
}
module "key_pair" {
  source = "./modules/key_pair"

  key_name = var.key_name

  # key_pair consumes no network output, so nothing would otherwise order it
  # against the network module's resources. Every module in a root that has a
  # network module waits for all of it (rules.md D-3).
  depends_on = [module.network]
}
module "eks_cluster" {
  source = "./modules/eks_cluster"

  name                   = var.cluster_name
  kubernetes_version     = var.kubernetes_version
  subnet_ids             = concat(module.network.public_subnet_ids, module.network.private_subnet_ids)
  endpoint_public_access = var.endpoint_public_access
  public_access_cidrs    = var.public_access_cidrs

  # Referencing module.network.*_subnet_ids only orders this module after the
  # specific aws_subnet resources behind those outputs, not after the NAT
  # gateways and route table associations that never surface as outputs
  # (rules.md D-3).
  depends_on = [module.network]
}
module "eks_vpc_cni_addon" {
  source = "./modules/eks_vpc_cni_addon"

  cluster_name = module.eks_cluster.cluster_name

  # bootstrap_self_managed_addons = false on the cluster means vpc-cni does not
  # exist until this addon creates it. As a DaemonSet it reaches ACTIVE with
  # zero nodes, so it is created before any node capacity - worker nodes need it
  # running to join the cluster Ready (rules.md C-4).
  depends_on = [module.network, module.eks_cluster]
}
module "eks_kube_proxy_addon" {
  source = "./modules/eks_kube_proxy_addon"

  cluster_name = module.eks_cluster.cluster_name

  # Same reasoning as eks_vpc_cni_addon: kube-proxy is a DaemonSet and must
  # exist before any node capacity (rules.md C-4).
  depends_on = [module.network, module.eks_cluster]
}
# The CloudWatch agent gets its credentials from this agent through a Pod
# Identity association rather than from an IRSA trust policy, so it has to be
# installed before the observability addon below.
module "eks_pod_identity_agent_addon" {
  source = "./modules/eks_pod_identity_agent_addon"

  cluster_name = module.eks_cluster.cluster_name

  # Also a DaemonSet, so it becomes ACTIVE with zero nodes (rules.md C-4).
  depends_on = [module.network, module.eks_cluster]
}
module "eks_node_group" {
  source = "./modules/eks_node_group"

  cluster_name    = module.eks_cluster.cluster_name
  node_group_name = var.node_group_name
  instance_types  = var.node_group_instance_types
  desired_size    = var.node_group_desired_size
  min_size        = var.node_group_min_size
  max_size        = var.node_group_max_size
  subnet_ids      = module.network.private_subnet_ids
  key_name        = module.key_pair.key_name

  # Nodes need vpc-cni and kube-proxy running to join the cluster Ready
  # (rules.md C-4).
  depends_on = [module.network, module.eks_vpc_cni_addon, module.eks_kube_proxy_addon]
}
module "eks_coredns_addon" {
  source = "./modules/eks_coredns_addon"

  cluster_name = module.eks_cluster.cluster_name

  # coredns is a Deployment and needs schedulable node capacity to leave its
  # DEGRADED state and become ACTIVE, so it is created after the node group
  # rather than before it (rules.md C-4).
  depends_on = [module.eks_node_group]
}
module "eks_metrics_server_addon" {
  source = "./modules/eks_metrics_server_addon"

  cluster_name = module.eks_cluster.cluster_name

  # metrics-server is a Deployment, so like coredns it needs schedulable node
  # capacity to become ACTIVE rather than DEGRADED (rules.md C-4).
  depends_on = [module.eks_node_group]
}
module "eks_cloudwatch_observability_addon" {
  source = "./modules/eks_cloudwatch_observability_addon"

  cluster_name                   = module.eks_cluster.cluster_name
  addon_version                  = var.cloudwatch_observability_addon_version
  container_log_components       = var.container_log_components
  disable_default_container_logs = var.disable_default_container_logs

  # The CloudWatch agent and Fluent Bit are DaemonSets and the addon's operator
  # is a Deployment, so this needs schedulable node capacity and working cluster
  # DNS. It also needs the Pod Identity agent already running, since that is how
  # its service account gets AWS credentials - and nothing in the values passed
  # above creates that dependency (rules.md D-2/C-4).
  depends_on = [module.network, module.eks_node_group, module.eks_coredns_addon, module.eks_pod_identity_agent_addon]
}
module "vscode_ec2" {
  source = "./modules/vscode_ec2"

  vpc_id                      = module.network.vpc_id
  subnet_id                   = module.network.public_subnet_a_id
  key_name                    = module.key_pair.key_name
  instance_type               = var.vscode_instance_type
  allow_inbound_from_anywhere = var.allow_inbound_from_anywhere
  # Lets the README association below know when the bootstrap has finished
  # (rules.md H-2). The module touches <path>/userdata as its last step.
  marker_file_path = var.marker_file_path
  # Joining the cluster security group is what lets this instance reach the
  # private API server endpoint. The module is handed an ID list and never
  # learns that it belongs to an EKS cluster (rules.md B-6).
  extra_security_group_ids = [module.eks_cluster.cluster_security_group_id]
  # An EKS cluster and this instance live in the same root module, so the
  # instance is the workbench for that cluster and carries all five tools:
  # code-server (the module itself), plus kubectl, eksctl, helm and docker
  # (rules.md H-1). None of them is used to create resources - Fluent Bit's
  # config arrives through the addon's configuration_values instead
  # (rules.md E-1/E-5).
  additional_user_data = <<-EOT
    dnf install -yq python3.13
    ln -sf /usr/bin/python3.13 /usr/bin/python
    python -m ensurepip --upgrade
    # Building container images needs a real daemon on the host, so unlike the
    # kubectl/helm steps this cannot become a provider resource (rules.md E-1).
    dnf install -yq docker
    systemctl enable --now docker
    usermod -aG docker ec2-user
    # code-server is already running from the module's bootstrap, so its process
    # predates the docker group and its integrated terminals inherit the groups
    # that process started with. Restarting picks the group up, which is what
    # makes docker usable from the IDE without loosening the socket's
    # permissions (rules.md H-1).
    systemctl restart code-server
    # Runs as ec2-user with HOME pinned: user data runs as root, so "~" can
    # still resolve to /root and the tools plus kubeconfig would land somewhere
    # the code-server session cannot see (rules.md H-1).
    sudo -Eu ec2-user bash << 'EOF'
    export HOME=/home/ec2-user
    cd $HOME
    mkdir -p $HOME/bin
    curl -sO https://s3.us-west-2.amazonaws.com/amazon-eks/${var.kubectl_download_version}/bin/linux/amd64/kubectl
    chmod +x ./kubectl && mv ./kubectl $HOME/bin/kubectl
    export PATH=$HOME/bin:$PATH
    echo 'export PATH=$HOME/bin:$PATH' >> ~/.bashrc
    # Order matters: sourcing the completion defines __start_kubectl, so a
    # "complete" line placed before it fails on every login.
    echo 'source /usr/share/bash-completion/bash_completion' >> ~/.bashrc
    echo 'source <(kubectl completion bash)' >> ~/.bashrc
    echo 'alias k=kubectl' >> ~/.bashrc
    echo 'complete -o default -F __start_kubectl k' >> ~/.bashrc
    PLATFORM=$(uname -s)_amd64
    curl -sLO "https://github.com/eksctl-io/eksctl/releases/latest/download/eksctl_$PLATFORM.tar.gz"
    tar -xzf eksctl_$PLATFORM.tar.gz -C /tmp && rm eksctl_$PLATFORM.tar.gz
    sudo install -m 0755 /tmp/eksctl /usr/local/bin && rm /tmp/eksctl
    curl -fsSL -o get_helm.sh https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3
    chmod 700 get_helm.sh && ./get_helm.sh
    aws configure set default.region ${data.aws_region.current.region}
    aws eks update-kubeconfig --region ${data.aws_region.current.region} --name ${module.eks_cluster.cluster_name}
    EOF
  EOT

  depends_on = [module.network]
}
# Granting the instance role cluster access joins two modules that know nothing
# about each other, so it belongs in the root rather than inside either one
# (rules.md C-1). Without it kubectl is installed but every call fails with
# "You must be logged in to the server" (rules.md H-1).
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

  depends_on = [aws_eks_access_entry.vscode_access_entry]
}
locals {
  # The modify and record_modifier filters in every rendered pipeline rename the
  # kubernetes metadata to these short field names and drop everything else, so
  # a Logs Insights query written against them works the same for every
  # component. Declared once and reused by both queries below rather than typed
  # out twice (rules.md B-5).
  log_insights_fields = "fields @timestamp, log, pod, container, node, namespace"
  # Every output this project exposes, defined once. outputs.tf projects these
  # and the README below renders them, so no value is written twice (rules.md
  # #5/#35). Adding an entry here is what makes an output possible, which is
  # what keeps the README from silently falling behind outputs.tf.
  outputs = {
    vscode_url = {
      order       = 1
      title       = "code-server"
      description = "Open the IDE here. The kubectl commands below are meant to be run from its terminal"
      value       = module.vscode_ec2.vscode_url
    }
    cluster_name = {
      order       = 2
      title       = "EKS cluster name"
      description = "Name of the EKS cluster, and the middle segment of every log group below"
      value       = module.eks_cluster.cluster_name
    }
    cluster_endpoint = {
      order       = 3
      title       = "EKS cluster endpoint"
      description = "API server endpoint of the EKS cluster"
      value       = module.eks_cluster.cluster_endpoint
    }
    cloudwatch_agent_role_arn = {
      order       = 4
      title       = "CloudWatch agent IAM role"
      description = "Role the agent assumes through EKS Pod Identity rather than IRSA, which is why there is no OIDC trust policy in this project"
      value       = module.eks_cloudwatch_observability_addon.agent_role_arn
    }
    container_log_components = {
      order       = 5
      title       = "Fluent Bit pipelines"
      description = "Components with their own log pipeline. Each was rendered from one template, so adding a component means adding a map entry rather than copying a 60-line config block"
      value       = join(",", module.eks_cloudwatch_observability_addon.container_log_component_names)
    }
    log_group_names = {
      order       = 6
      title       = "CloudWatch log groups"
      description = "One log group per component, instead of the addon's two catch-all groups. Created by Fluent Bit on first write, so a group is missing until its component logs something"
      value       = join("\n", module.eks_cloudwatch_observability_addon.log_group_names)
    }
    fluent_bit_pods_command = {
      order       = 7
      title       = "1. Check Fluent Bit is running"
      description = "The Fluent Bit and CloudWatch agent DaemonSets, one pod per node. A CrashLoopBackOff here usually means a malformed pipeline, and its logs name the offending file"
      value       = "kubectl -n ${module.eks_cloudwatch_observability_addon.namespace} get pods -o wide"
    }
    fluent_bit_config_command = {
      order       = 8
      title       = "2. Read the config that was applied"
      description = "The rendered pipelines as Fluent Bit actually received them, which is the fastest way to confirm the addon took the configuration_values"
      value       = "kubectl -n ${module.eks_cloudwatch_observability_addon.namespace} get configmap fluent-bit-config -o yaml"
    }
    log_insights_url = {
      order       = 9
      title       = "3. Open Logs Insights"
      description = "Select one of the log groups above, then run either query below"
      value       = module.eks_cloudwatch_observability_addon.log_insights_url
    }
    log_insights_query_by_node = {
      order       = 10
      title       = "4. Query one node's logs"
      description = "Replace the node name with one from the pod listing in step 1. The node field exists because the modify filter renames Fluent Bit's host field to it"
      value       = "${local.log_insights_fields} | filter node = \"ip-10-0-0-1.ec2.internal\" | sort @timestamp desc"
    }
    log_insights_query_by_container = {
      order       = 11
      title       = "5. Query one container's logs"
      description = "Same fields, filtered by container instead. aws-node is the vpc-cni DaemonSet's container, so this reads the vpc-cni log group"
      value       = "${local.log_insights_fields} | filter container = \"aws-node\" | sort @timestamp desc"
    }
  }
  # Iterating local.outputs directly would order sections by key, which puts
  # "2. Read the config" above "1. Check Fluent Bit is running". Re-keying by the
  # order field and taking values() sorts by that instead - values() returns a
  # map's values ordered by key - so the README reads in the order the demo is
  # run, and the order is still fully determined by the configuration rather
  # than shuffling between applies.
  readme_ordered = values({
    for key, entry in local.outputs : format("%02d-%s", entry.order, key) => entry
  })
  # Rendered from the same map, so an added output shows up here without anyone
  # remembering to edit two places (rules.md H-2).
  readme_body = join("\n", concat(
    ["# ${var.cluster_name}", ""],
    flatten([for entry in local.readme_ordered : [
      "## ${entry.title}", "", entry.description, "", "```", entry.value, "```", "",
    ]]),
  ))
}
# The work happens inside code-server in a browser, where "terraform output" is
# not available, so every output above is also written to a README in the home
# directory the IDE opens (rules.md H-2).
resource "aws_ssm_association" "vscode_readme" {
  name                             = "AWS-RunShellScript"
  wait_for_success_timeout_seconds = var.readme_timeout_seconds
  targets {
    key    = "InstanceIds"
    values = [module.vscode_ec2.instance_id]
  }
  parameters = {
    # The until loop, not depends_on or wait_for_success_timeout_seconds, is
    # what orders this after the instance bootstrap, and the marker this command
    # leaves behind is what a later association would wait on (rules.md D-5).
    # SSM runs as root, hence the chown - without it the file is not editable
    # from the IDE.
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
