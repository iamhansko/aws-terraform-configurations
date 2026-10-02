data "aws_region" "current" {}
module "network" {
  source = "./modules/network"

  vpc_cidr_block = var.vpc_cidr_block
  # The subnets are small on purpose. Everything else in this root exists to put
  # enough pods on these nodes that eleven addresses per subnet is not enough
  # (rules.md B-3).
  subnet_prefix_length = var.subnet_prefix_length
}
module "key_pair" {
  source = "./modules/key_pair"

  key_name = var.key_name

  # key_pair consumes no network output, so nothing would otherwise order it against
  # the network module's resources (rules.md D-3).
  depends_on = [module.network]
}
# The variant. A second CIDR on the VPC, a subnet per zone carrying
# kubernetes.io/role/cni, and a route out of each - which is all enhanced subnet
# discovery needs. No ENIConfig custom resource, no node restart.
module "cni_subnets" {
  source = "./modules/cni_subnets"

  vpc_id                     = module.network.vpc_id
  secondary_cidr_block       = var.secondary_cidr_block
  subnet_prefix_length       = var.cni_subnet_prefix_length
  availability_zone_suffixes = var.availability_zone_suffixes
  # A map keyed by AZ letter rather than a list: these IDs are another module's
  # output and unknown until apply, while the for_each that consumes them needs
  # keys known during plan (rules.md B-8).
  nat_gateway_ids = module.network.nat_gateway_ids

  depends_on = [module.network]
}
module "eks_cluster" {
  source = "./modules/eks_cluster"

  name               = var.cluster_name
  kubernetes_version = var.kubernetes_version
  # The primary subnets only. The tagged subnets are deliberately not handed to the
  # cluster: the CNI finds them by tag at runtime, and listing them here would put
  # control plane interfaces in the very subnets the demo is filling with pods.
  subnet_ids             = concat(module.network.public_subnet_ids, module.network.private_subnet_ids)
  endpoint_public_access = var.endpoint_public_access
  public_access_cidrs    = var.public_access_cidrs

  # Referencing module.network.*_subnet_ids only orders this after the specific
  # aws_subnet resources behind those outputs, not after the NAT gateways and route
  # table associations that never surface as outputs (rules.md D-3).
  depends_on = [module.network]
}
module "eks_vpc_cni_addon" {
  source = "./modules/eks_vpc_cni_addon"

  cluster_name = module.eks_cluster.cluster_name
  # What this project is for. The _monolithic template set the same variable, but as a
  # YAML string built by hand in configuration_values; here it is one typed bool
  # rendered into the addon's schema (rules.md E-5). It replaces the
  # "kubectl set env daemonset aws-node -n kube-system ENABLE_SUBNET_DISCOVERY=true"
  # step the AWS documentation offers as the alternative (rules.md E-1).
  #
  # env, not a top-level key: this one really is an aws-node environment variable,
  # unlike enableNetworkPolicy, which is not. Putting a top-level key under env - or an
  # env var at the top level - renders valid JSON that the addon ignores.
  env = {
    ENABLE_SUBNET_DISCOVERY = tostring(var.enable_subnet_discovery)
  }
  # addon_version is left at null so EKS picks its default for this Kubernetes version.
  # Enhanced subnet discovery needs 1.18.0 or later, and the default for 1.31+ is well
  # past that; pinning an older version here would switch the feature off by making the
  # environment variable meaningless rather than by any visible error.

  # bootstrap_self_managed_addons = false on the cluster means vpc-cni does not exist
  # until this addon creates it. As a DaemonSet it reaches ACTIVE with zero nodes, so it
  # comes before any capacity (rules.md C-4) - and nodes need it to join Ready.
  depends_on = [module.network, module.eks_cluster]
}
module "eks_kube_proxy_addon" {
  source = "./modules/eks_kube_proxy_addon"

  cluster_name = module.eks_cluster.cluster_name

  # Same reasoning as eks_vpc_cni_addon (rules.md C-4).
  depends_on = [module.network, module.eks_cluster]
}
module "eks_node_group" {
  source = "./modules/eks_node_group"

  cluster_name   = module.eks_cluster.cluster_name
  instance_types = var.node_group_instance_types
  desired_size   = var.node_group_desired_size
  min_size       = var.node_group_min_size
  max_size       = var.node_group_max_size
  # Private subnets only. The nodes' own interfaces live here; their pods' interfaces
  # are what spill over into the tagged subnets.
  subnet_ids = module.network.private_subnet_ids

  # module.cni_subnets is here for both directions of the graph. On the way up, a node
  # that boots before its zone has a tagged subnet fills its own /28 and has nowhere
  # else to look. On the way down it matters more: Terraform destroys in reverse
  # dependency order, and AWS refuses to delete a subnet while interfaces remain in it.
  # Without this edge nothing connects the node group to those subnets, so Terraform is
  # free to delete them in parallel with the nodes whose pod interfaces are still there,
  # and the destroy fails with DependencyViolation on a subnet - which reads as a
  # leftover resource rather than an ordering problem (rules.md D-2).
  depends_on = [module.network, module.cni_subnets, module.eks_vpc_cni_addon, module.eks_kube_proxy_addon]
}
module "eks_coredns_addon" {
  source = "./modules/eks_coredns_addon"

  cluster_name = module.eks_cluster.cluster_name

  # coredns is a Deployment and needs schedulable capacity to leave DEGRADED and become
  # ACTIVE (rules.md C-4). Its two pods also compete for the same scarce addresses as
  # the pressure workload, which is why it is created before that workload rather than
  # after: CoreDNS losing the race for an address would break name resolution
  # cluster-wide and look like a much larger problem than a full subnet.
  depends_on = [
  module.network, module.eks_node_group]
}
module "inflate_workload" {
  source = "./modules/inflate_workload"

  replicas = var.inflate_replicas

  # kubectl_manifest resources against the cluster's API server, so they need the nodes
  # they will be scheduled onto - and ordering the module after the node group makes
  # terraform destroy remove the pods while their nodes are still there to release the
  # addresses and interfaces (rules.md D-4). That release is what lets the tagged
  # subnets be deleted at all.
  depends_on = [
  module.network, module.eks_node_group, module.eks_coredns_addon]
}
module "vscode_ec2" {
  source = "./modules/vscode_ec2"

  vpc_id                      = module.network.vpc_id
  subnet_id                   = module.network.public_subnet_a_id
  key_name                    = module.key_pair.key_name
  instance_type               = var.vscode_instance_type
  allow_inbound_from_anywhere = var.allow_inbound_from_anywhere
  marker_file_path            = var.marker_file_path
  # Joining the cluster security group is what lets this instance reach the API server.
  # The module is handed an ID list and never learns it belongs to an EKS cluster
  # (rules.md B-6).
  extra_security_group_ids = [module.eks_cluster.cluster_security_group_id]

  # An EKS cluster and this instance share a root module, so it is the workbench for that
  # cluster and carries all five tools (rules.md H-1). None of them creates anything: the
  # pressure workload the _monolithic template applied from here is a Terraform resource
  # now (rules.md E-1).
  #
  # Two bugs from that template are fixed here rather than carried over. It ran
  # "exec bash" partway through, which replaces the shell and silently discarded every
  # remaining line - update-kubeconfig, eksctl and helm were all after it, so none of
  # them ever ran, and the instance came up without a kubeconfig. And it pulled eksctl
  # from weaveworks; eksctl-io is the project's own org (rules.md H-1).
  additional_user_data = <<-EOT
    dnf install -yq docker
    systemctl enable --now docker
    usermod -aG docker ec2-user
    # code-server is already running and predates the docker group, so its terminals
    # would not have it without a restart.
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
    # Order matters: kubectl's completion defines __start_kubectl, and that has to exist
    # before complete names it, or every login prints "function not found"
    # (rules.md H-1).
    echo 'source /usr/share/bash-completion/bash_completion' >> ~/.bashrc
    echo 'source <(kubectl completion bash)' >> ~/.bashrc
    echo 'alias k=kubectl' >> ~/.bashrc
    echo 'complete -o default -F __start_kubectl k' >> ~/.bashrc
    PLATFORM=$(uname -s)_amd64
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

  depends_on = [aws_eks_access_entry.vscode_access_entry]
}
locals {
  # AWS reserves five addresses in every subnet - the network address, the broadcast
  # address, the VPC router, the DNS resolver and one held in reserve - so a /28's
  # sixteen addresses come to eleven. Stated once here and read by two outputs, rather
  # than written out as prose that goes stale the moment the prefix length changes
  # (rules.md B-5).
  usable_addresses_per_subnet     = pow(2, 32 - var.subnet_prefix_length) - 5
  usable_addresses_per_cni_subnet = pow(2, 32 - var.cni_subnet_prefix_length) - 5
  # Every output this project exposes, defined once. outputs.tf projects these and the
  # README below renders them, so no value expression is written twice (rules.md B-5/H-2).
  # Adding an entry here is what makes an output possible, which is what keeps the README
  # from falling behind outputs.tf.
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
      description = "Name of the EKS cluster"
      value       = module.eks_cluster.cluster_name
    }
    cluster_endpoint = {
      order       = 3
      title       = "EKS cluster endpoint"
      description = "API server endpoint. Public so the kubectl provider could reach it during apply - narrow public_access_cidrs to your own address"
      value       = module.eks_cluster.cluster_endpoint
    }
    primary_subnets = {
      order       = 4
      title       = "Where the nodes are, and how little room they have"
      description = "The subnets the worker nodes launch into. These are the addresses pods get by default, and there are deliberately far too few of them - a node of this size can hold seventeen pods on its own"
      value       = join(", ", [for suffix, cidr in module.network.private_subnet_cidr_blocks : "${suffix}=${cidr} (${local.usable_addresses_per_subnet} usable)"])
    }
    cni_subnets = {
      order       = 5
      title       = "Where the extra addresses come from"
      description = "The tagged subnets, carved out of a second CIDR added to the same VPC. Not attached to the cluster and not where any node runs: the CNI finds them by tag and creates pod interfaces there once a node's own subnet is empty"
      value       = join(", ", [for suffix, cidr in module.cni_subnets.subnet_cidr_blocks : "${suffix}=${cidr} (${local.usable_addresses_per_cni_subnet} usable)"])
    }
    cni_discovery_tag = {
      order       = 6
      title       = "The tag that does the work"
      description = "This exact string is the whole interface between the VPC and the CNI. Nothing validates it: a subnet without it is never considered, and the only symptom is pods that still cannot get an address"
      value       = module.cni_subnets.discovery_tag
    }
    subnet_discovery_setting = {
      order       = 7
      title       = "The switch, as the addon received it"
      description = "The JSON the vpc-cni addon was configured with. Read it when the demo shows nothing: an environment variable that landed in the wrong place is valid JSON the addon silently ignores (rules.md E-5)"
      value       = module.eks_vpc_cni_addon.configuration_values
    }
    rollout_status_command = {
      order       = 8
      title       = "1. Wait for the pressure workload"
      description = "Fifty pods, each holding one VPC address. Run this first: a pod still waiting for an address looks exactly like one that was never scheduled, so nothing below means anything until this returns"
      value       = module.inflate_workload.rollout_status_command
    }
    address_distribution_command = {
      order       = 9
      title       = "2. Count pod addresses by range"
      description = "The headline result. One group means the nodes' own subnets still had room and discovery has not been needed; two groups - 10.0 and 100.64 - means the CNI ran out, found the tagged subnets and started allocating from them"
      value       = module.inflate_workload.address_distribution_command
    }
    pod_status_command = {
      order       = 10
      title       = "3. See it per pod"
      description = "The same thing one pod at a time, sorted by address so the two ranges appear as two blocks. Pods on the same node with addresses in different ranges is the point: one node, two subnets, no configuration on the node itself"
      value       = module.inflate_workload.pod_status_command
    }
    subnet_check_command = {
      order       = 11
      title       = "4. Read the free address counts"
      description = "Lists subnets through the same tag filter the CNI uses, with the free count it ranks them by. The primary subnets are not in this list at all - they are used because the node is in them, not because they are discovered"
      value       = module.cni_subnets.subnet_check_command
    }
    interface_check_command = {
      order       = 12
      title       = "5. See which subnet each interface is in"
      description = "Interfaces described as aws-K8S-... appearing in the tagged subnets while the nodes themselves stay in the private ones. This is the same fact as the pod addresses, seen from the VPC's side"
      value       = module.cni_subnets.interface_check_command
    }
    subnet_discovery_check_command = {
      order       = 13
      title       = "6. Confirm the switch reached the DaemonSet"
      description = "What the addon configuration above turned into, on the pods that act on it. Empty output means the environment variable is not set and the CNI is using its own default rather than this project's setting"
      value       = "kubectl describe ds aws-node -n kube-system | grep ENABLE_SUBNET_DISCOVERY"
    }
    pending_pods_command = {
      order       = 14
      title       = "7. Pods that never got an address"
      description = "Empty is the expected result, and the failure this project exists to prevent. Pods stuck here while the nodes have CPU and memory to spare is what address exhaustion looks like from Kubernetes - nothing in the message mentions subnets"
      value       = module.inflate_workload.pending_pods_command
    }
    cni_log_command = {
      order       = 15
      title       = "8. The CNI's own account"
      description = "Which subnets the agent considered and which it chose. This is where a tag typo shows up: the agent simply never mentions the subnet you expected, rather than reporting an error about it"
      value       = module.inflate_workload.cni_log_command
    }
    raise_pressure_command = {
      order       = 16
      title       = "9. Turn the pressure up"
      description = "Raise the pod count and watch the second range grow. Through Terraform rather than kubectl scale, so the value lives in state instead of being put back by the next apply (rules.md B-4). Note the node count is the other limit: a t3.medium holds seventeen pods regardless of how many addresses are available"
      value       = "terraform apply -var inflate_replicas=${var.inflate_replicas * 2}"
    }
    update_kubeconfig_command = {
      order       = 17
      title       = "Re-point kubectl"
      description = "User data already ran this, so kubectl works out of the box. Re-run it if the kubeconfig is ever lost"
      value       = "aws eks update-kubeconfig --region ${data.aws_region.current.region} --name ${module.eks_cluster.cluster_name}"
    }
  }
  # Iterating local.outputs directly would order sections by key. Re-keying by the order
  # field and taking values() - which returns a map's values ordered by key - makes the
  # README read top to bottom while the order stays decided by configuration.
  readme_ordered = values({
    for key, entry in local.outputs : format("%02d-%s", entry.order, key) => entry
  })
  readme_body = join("\n", concat(
    ["# ${var.cluster_name}", ""],
    flatten([for entry in local.readme_ordered : [
      "## ${entry.title}", "", entry.description, "", "```", entry.value, "```", "",
    ]]),
  ))
}
# The work happens inside code-server in a browser, where terraform output is not
# available, so every output above is also written to a README in the home directory the
# IDE opens (rules.md H-2). Combining several modules' outputs is the root's job, so this
# lives here rather than inside the instance module.
resource "aws_ssm_association" "vscode_readme" {
  name                             = "AWS-RunShellScript"
  wait_for_success_timeout_seconds = var.readme_timeout_seconds
  targets {
    key    = "InstanceIds"
    values = [module.vscode_ec2.instance_id]
  }
  parameters = {
    # The until loop, not depends_on or wait_for_success_timeout_seconds, is what orders
    # this after the bootstrap (rules.md D-5). The marker path comes back out of the
    # module it was passed into, so it is defined once (rules.md B-5).
    #
    # SSM runs as root, hence the chown.
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
