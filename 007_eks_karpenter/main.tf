data "aws_region" "current" {}
# Resolves CloudFront's origin-facing address ranges for this region at plan
# time. Replaces the _monolithic template's AWSRegions2PrefixListId mapping,
# a hand-maintained region-to-prefix-list table that silently had no entry for
# newer regions.
data "aws_ec2_managed_prefix_list" "cloudfront_origin_facing" {
  count = var.enable_cloudfront ? 1 : 0
  name  = var.cloudfront_origin_facing_prefix_list_name
}
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
  # The discovery tag is what the EC2NodeClass subnet selector matches on, so
  # Karpenter only ever launches nodes into this cluster's private subnets. The
  # kubernetes.io/role tags are kept so the AWS Load Balancer Controller can
  # still auto-discover subnets.
  private_subnet_tags = {
    "kubernetes.io/role/internal-elb" = "1"
    (var.karpenter_discovery_tag_key) = var.cluster_name
  }
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
module "eks_pod_identity_agent_addon" {
  source = "./modules/eks_pod_identity_agent_addon"

  cluster_name = module.eks_cluster.cluster_name

  # Also a DaemonSet, so it becomes ACTIVE with zero nodes (rules.md C-4).
  depends_on = [module.network, module.eks_cluster]
}
# Karpenter cannot provision the nodes its own controller runs on, so a small
# managed node group is a prerequisite for it, not a duplicate of it. Everything
# beyond this baseline is left to Karpenter.
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
module "karpenter" {
  source = "./modules/karpenter"

  cluster_name      = module.eks_cluster.cluster_name
  oidc_provider_arn = module.eks_cluster.oidc_provider_arn
  oidc_issuer_host  = module.eks_cluster.oidc_issuer_host
  chart_version     = var.karpenter_chart_version
  capacity_types    = var.karpenter_capacity_types
  # Selector tags are injected rather than discovered, so the module never has
  # to know which network module tagged the subnets or that EKS owns the
  # security group (rules.md B-6).
  subnet_selector_tags = {
    (var.karpenter_discovery_tag_key) = var.cluster_name
  }
  # EKS tags the cluster security group it creates with aws:eks:cluster-name,
  # so selecting on it attaches Karpenter's nodes to the same group the managed
  # node group's nodes use.
  security_group_selector_tags = {
    "aws:eks:cluster-name" = module.eks_cluster.cluster_name
  }
  instance_categories = var.karpenter_instance_categories
  instance_types      = var.karpenter_instance_types
  cpu_limit           = var.karpenter_cpu_limit
  # Every node from this pool carries these labels, and the stress demo below
  # selects on them, which is what keeps its pods off the managed node group.
  node_labels = var.karpenter_node_labels
  node_tags = {
    Name = "${var.prefix}-karpenter-node"
  }

  # The controller pod needs schedulable capacity on the managed node group and
  # working cluster DNS before it can reach the EKS API, and wait = true on its
  # Helm release would otherwise time out. Ordering the module after coredns
  # also makes terraform destroy remove the NodePool - letting Karpenter drain
  # its nodes - while the controller is still running (rules.md D-2/D-4).
  depends_on = [module.network, module.eks_node_group, module.eks_coredns_addon]
}
# The workload that makes Karpenter do something. Created at zero replicas, so
# it provisions nothing until someone scales it up.
module "stress_demo" {
  source = "./modules/stress_demo"

  name          = var.stress_demo_name
  namespace     = var.stress_demo_namespace
  replica_count = var.stress_demo_replica_count
  cpu_request   = var.stress_demo_cpu_request
  # Reuses the very labels the NodePool was given, so the selector cannot drift
  # from the labels the nodes actually carry (rules.md B-5).
  node_selector = module.karpenter.node_labels

  # Karpenter has to be installed, with its NodePool and EC2NodeClass applied,
  # before these pods have anywhere to go - the CRDs are what turn a Pending pod
  # into a node. Ordering the module after karpenter also makes terraform
  # destroy delete the Deployment first, so Karpenter drains and removes its own
  # nodes while the controller is still running (rules.md D-2/D-4).
  depends_on = [module.network, module.karpenter]
}
module "vscode_ec2" {
  source = "./modules/vscode_ec2"

  vpc_id        = module.network.vpc_id
  subnet_id     = module.network.public_subnet_a_id
  key_name      = module.key_pair.key_name
  instance_type = var.vscode_instance_type
  # With CloudFront in front, only CloudFront's origin-facing ranges may reach
  # code-server, so the editor is never directly exposed to the internet.
  ingress_prefix_list_ids     = var.enable_cloudfront ? [data.aws_ec2_managed_prefix_list.cloudfront_origin_facing[0].id] : []
  allow_inbound_from_anywhere = var.allow_inbound_from_anywhere
  # Lets the README association below know when the bootstrap has finished
  # (rules.md H-2). The module touches <path>/userdata as its last step.
  marker_file_path = var.marker_file_path
  # Joining the cluster security group is what lets this instance reach the
  # private API server endpoint (rules.md B-6).
  extra_security_group_ids = [module.eks_cluster.cluster_security_group_id]
  # An EKS cluster and this instance live in the same root module, so the
  # instance is the workbench for that cluster and carries all five tools:
  # code-server (the module itself), plus kubectl, eksctl, helm and docker
  # (rules.md H-1). None of them is behind a flag, and none of them is used to
  # create resources - that stays with the helm and kubectl providers.
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
    su - ec2-user << 'EOF'
    export HOME=/home/ec2-user
    cd $HOME
    curl -sO https://s3.us-west-2.amazonaws.com/amazon-eks/${var.kubectl_download_version}/bin/linux/amd64/kubectl
    chmod +x ./kubectl
    mkdir -p $HOME/bin && mv ./kubectl $HOME/bin/kubectl && export PATH=$HOME/bin:$PATH
    echo 'export PATH=$HOME/bin:$PATH' >> ~/.bashrc
    echo 'source /usr/share/bash-completion/bash_completion' >> ~/.bashrc
    echo 'source <(kubectl completion bash)' >> ~/.bashrc
    echo 'alias k=kubectl' >> ~/.bashrc
    echo 'complete -o default -F __start_kubectl k' >> ~/.bashrc
    ARCH=amd64
    PLATFORM=$(uname -s)_$ARCH
    curl -sLO "https://github.com/eksctl-io/eksctl/releases/latest/download/eksctl_$PLATFORM.tar.gz"
    tar -xzf eksctl_$PLATFORM.tar.gz -C /tmp && rm eksctl_$PLATFORM.tar.gz
    sudo install -m 0755 /tmp/eksctl /usr/local/bin && rm /tmp/eksctl
    curl -fsSL -o get_helm.sh https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3
    chmod 700 get_helm.sh
    ./get_helm.sh
    aws configure set default.region ${data.aws_region.current.region}
    aws eks update-kubeconfig --region ${data.aws_region.current.region} --name ${module.eks_cluster.cluster_name}
    EOF
  EOT

  depends_on = [module.network]
}
module "vscode_cloudfront" {
  count  = var.enable_cloudfront ? 1 : 0
  source = "./modules/vscode_cloudfront"

  origin_domain_name = module.vscode_ec2.public_dns
  # Taken from the instance module rather than restating 8000, so the origin
  # port cannot drift from what code-server binds to (rules.md B-5).
  origin_http_port  = module.vscode_ec2.code_server_port
  cache_policy_name = "${var.prefix}-vscode-code-server"
  comment           = "code-server on ${var.prefix} bastion"

  depends_on = [module.network]
}
# Granting the instance role cluster access joins two modules that know nothing
# about each other, so it belongs in the root rather than inside either one
# (rules.md C-1).
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
  # Every output this project exposes, defined once. outputs.tf projects these
  # and the README below renders them, so no value is written twice (rules.md
  # #5/#35). Adding an entry here is what makes an output possible, which is
  # what keeps the README from silently falling behind outputs.tf.
  outputs = {
    vscode_url = {
      order       = 1
      title       = "code-server"
      description = "Open the IDE here. The rest of these commands are meant to be run from its terminal"
      value       = var.enable_cloudfront ? module.vscode_cloudfront[0].url : module.vscode_ec2.vscode_url
    }
    cluster_name = {
      order       = 2
      title       = "EKS cluster name"
      description = "Name of the EKS cluster"
      value       = module.eks_cluster.cluster_name
    }
    cluster_endpoint = {
      order       = 3
      title       = "EKS cluster endpoint"
      description = "API server endpoint of the EKS cluster"
      value       = module.eks_cluster.cluster_endpoint
    }
    node_group_name = {
      order       = 4
      title       = "Managed node group"
      description = "Node group hosting the Karpenter controller. Karpenter cannot provision the nodes its own controller runs on, so this baseline capacity is a prerequisite rather than a duplicate of it"
      value       = module.eks_node_group.node_group_name
    }
    karpenter_node_role_name = {
      order       = 6
      title       = "Karpenter node IAM role"
      description = "Role Karpenter-provisioned nodes run as, which EC2NodeClass.spec.role references"
      value       = module.karpenter.node_role_name
    }
    karpenter_node_pool_name = {
      order       = 5
      title       = "Karpenter NodePool"
      description = "NodePool Karpenter provisions against: kubectl get nodepool, kubectl describe nodepool"
      value       = module.karpenter.node_pool_name
    }
    karpenter_node_labels = {
      order       = 7
      title       = "Karpenter node labels"
      description = "Labels every Karpenter-provisioned node carries, and what the stress demo's nodeSelector requires. Rendered as key=value pairs so this reads the same in the README as it does in kubectl output"
      value       = join(",", [for key, value in module.karpenter.node_labels : "${key}=${value}"])
    }
    karpenter_instance_types = {
      order       = 8
      title       = "Karpenter instance types"
      description = "Instance types the NodePool is pinned to, or empty when Karpenter is free to choose within its category and generation requirements"
      value       = join(",", module.karpenter.instance_types)
    }
    stress_demo_name = {
      order       = 9
      title       = "Stress demo Deployment"
      description = "Deployment declared at zero replicas. Scaling it is what makes Karpenter provision nodes"
      value       = module.stress_demo.name
    }
    stress_demo_scale_up_command = {
      order       = 10
      title       = "1. Scale the demo up"
      description = "Creates pods no existing node can fit, so Karpenter launches new nodes for them"
      value       = module.stress_demo.scale_up_command
    }
    stress_demo_nodes_watch_command = {
      order       = 11
      title       = "2. Watch nodes arrive"
      description = "Karpenter-provisioned nodes appear with the NodePool labels shown as columns"
      value       = module.stress_demo.nodes_watch_command
    }
    stress_demo_pods_watch_command = {
      order       = 12
      title       = "3. Watch the pods schedule"
      description = "The demo pods move from Pending to Running as those nodes become Ready"
      value       = module.stress_demo.pods_watch_command
    }
    stress_demo_scale_down_command = {
      order       = 13
      title       = "4. Scale the demo down"
      description = "Removes the pods, leaving the nodes empty so consolidation deletes them after the NodePool's consolidateAfter window"
      value       = module.stress_demo.scale_down_command
    }
  }
  # Iterating local.outputs directly would order sections by key, which puts
  # "2. Watch nodes arrive" above "1. Scale the demo up". Re-keying by the order
  # field and taking values() sorts by that instead - values() returns a map's
  # values ordered by key - so the README reads in the order the demo is run,
  # and the order is still fully determined by the configuration rather than
  # shuffling between applies.
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
    # The until loop, not depends_on or wait_for_success_timeout_seconds, is what
    # orders this after the instance bootstrap, and the marker this command
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
