data "aws_region" "current" {}
module "network" {
  source = "./modules/network"

  vpc_name                 = "${var.cluster_name}-vpc"
  internet_gateway_name    = "${var.cluster_name}-igw"
  public_subnet_name       = "${var.cluster_name}-public"
  private_subnet_name      = "${var.cluster_name}-private"
  public_route_table_name  = "${var.cluster_name}-public-rt"
  private_route_table_name = "${var.cluster_name}-private-rt"
  nat_gateway_name         = "${var.cluster_name}-natgw"
  # No subnet tags: nothing here creates a load balancer, so there is nothing for the AWS Load
  # Balancer Controller to auto-discover subnets for (rules.md G-1).
  #
  # Both interfaces a multi-NIC pod gets come from the node's own subnet, so nothing here needs a
  # second set of subnets - which is the difference between this project and the Multus ones next
  # door.
}
module "key_pair" {
  source = "./modules/key_pair"

  key_name = var.key_name

  # key_pair consumes no network output, so nothing would otherwise order it against the network
  # module's resources (rules.md D-3).
  depends_on = [module.network]
}
module "eks_cluster" {
  source = "./modules/eks_cluster"

  name                   = var.cluster_name
  kubernetes_version     = var.kubernetes_version
  subnet_ids             = concat(module.network.public_subnet_ids, module.network.private_subnet_ids)
  endpoint_public_access = var.endpoint_public_access
  public_access_cidrs    = var.public_access_cidrs

  # Referencing module.network.*_subnet_ids only orders this after the specific aws_subnet
  # resources behind those outputs, not after the NAT gateways and route table associations that
  # never surface as outputs (rules.md D-3).
  depends_on = [module.network]
}
# The subject of this project. ENABLE_MULTI_NIC is what makes a pod carrying the nicConfig
# annotation get an interface from the node's second network card, and it reaches the aws-node
# DaemonSet through the addon's configuration_values rather than a "kubectl set env daemonset
# aws-node -n kube-system ENABLE_MULTI_NIC=true" call from a shell - which is how AWS documents it
# and how the _monolithic template would have had to do it if it had not used the addon
# (rules.md E-5).
module "eks_vpc_cni_addon" {
  source = "./modules/eks_vpc_cni_addon"

  cluster_name  = module.eks_cluster.cluster_name
  addon_version = var.vpc_cni_addon_version
  env = {
    ENABLE_MULTI_NIC = tostring(var.enable_multi_nic)
  }

  # bootstrap_self_managed_addons = false on the cluster means vpc-cni does not exist until this
  # addon creates it. As a DaemonSet it reaches ACTIVE with zero nodes, so it comes before any
  # capacity - and nodes need it to join Ready (rules.md C-4). Here the order matters twice: a node
  # that joins before the addon carries ENABLE_MULTI_NIC would run a CNI that has never been told
  # about the feature.
  depends_on = [module.network, module.eks_cluster]
}
module "eks_kube_proxy_addon" {
  source = "./modules/eks_kube_proxy_addon"

  cluster_name = module.eks_cluster.cluster_name

  # Same reasoning as eks_vpc_cni_addon (rules.md C-4).
  depends_on = [module.network, module.eks_vpc_cni_addon]
}
# The node the second interface comes from. Its instance type is the second half of the feature:
# more than one network card, which only the largest sizes of a few families have.
#
# The _monolithic template carried a src/userdata.sh that creates two extra ENIs with the AWS CLI,
# tags them node.k8s.amazonaws.com/no_manage=true and attaches them at device indexes 1 and 2 - and
# never wired it to anything, because its node group had no launch template. That script belongs to
# the Multus projects next door, where the CNI does not manage the extra interfaces and something
# has to create them by hand. The multi-NIC feature here does the attaching itself, so no launch
# template user data is needed and the file is left as reference rather than reproduced.
module "eks_node_group" {
  source = "./modules/eks_node_group"

  cluster_name    = module.eks_cluster.cluster_name
  node_group_name = "core-nodegroup"
  instance_types  = var.node_group_instance_types
  desired_size    = var.node_group_desired_size
  min_size        = var.node_group_min_size
  max_size        = var.node_group_max_size
  subnet_ids      = module.network.private_subnet_ids
  key_name        = module.key_pair.key_name

  # Nodes need vpc-cni and kube-proxy running to join the cluster Ready (rules.md C-4).
  depends_on = [module.network, module.eks_vpc_cni_addon, module.eks_kube_proxy_addon]
}
module "eks_coredns_addon" {
  source = "./modules/eks_coredns_addon"

  cluster_name = module.eks_cluster.cluster_name

  # coredns is a Deployment and needs schedulable capacity to leave DEGRADED and become ACTIVE
  # (rules.md C-4).
  depends_on = [
  module.network, module.eks_node_group]
}
module "multi_homed_workload" {
  source = "./modules/multi_homed_workload"

  name                        = var.multi_homed_name
  namespace                   = var.multi_homed_namespace
  enable_multi_nic_annotation = var.multi_homed_annotate

  # A kubectl_manifest resource against the cluster's API server. Ordering the module after the
  # nodes is what makes terraform destroy remove the Deployment while there is still a kubelet to
  # delete its pod - and the pod has to be scheduled onto a node whose CNI already knows about
  # multi-NIC, which is what the addon dependency above gives it (rules.md D-4).
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
  # Joining the cluster security group is what lets this instance reach the API server. The module
  # is handed an ID list and never learns it belongs to an EKS cluster (rules.md B-6).
  extra_security_group_ids = [module.eks_cluster.cluster_security_group_id]

  # An EKS cluster and this instance share a root module, so it is the workbench for that cluster
  # and carries all five tools (rules.md H-1). None of them creates anything: the demo Deployment
  # the _monolithic template applied from here is a Terraform resource now (rules.md E-1).
  #
  # Bugs from that template that are not carried over. It ran "exec bash" partway through, which
  # replaces the shell and silently discarded every remaining line - eksctl, helm, the AWS Load
  # Balancer Controller install and the kubectl apply of the demo Deployment were all after it, so
  # on a real boot none of them ran and the cluster had nothing to demonstrate. It pulled eksctl
  # from weaveworks rather than eksctl-io. And it wrote the "complete" line for the k alias into
  # .bashrc before the line that defines __start_kubectl, so every login printed a "function not
  # found" error (rules.md H-1).
  additional_user_data = <<-EOT
    dnf install -yq docker
    systemctl enable --now docker
    usermod -aG docker ec2-user
    # code-server is already running and predates the docker group, so its terminals would not
    # have it without a restart.
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
    # Order matters: kubectl's completion defines __start_kubectl, and that has to exist before
    # complete names it, or every login prints "function not found" (rules.md H-1).
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
    rm get_helm.sh
    aws configure set default.region ${data.aws_region.current.region}
    aws eks update-kubeconfig --region ${data.aws_region.current.region} --name ${module.eks_cluster.cluster_name}
    EOF
  EOT

  depends_on = [module.network]
}
# Granting the bastion's instance role cluster access joins two modules that know nothing about
# each other, so it belongs in the root (rules.md C-1).
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
  # Every output this project exposes, defined once. outputs.tf projects these and the README below
  # renders them, so no value expression is written twice (rules.md B-5/H-2).
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
    multi_nic_configuration = {
      order       = 4
      title       = "The three things that have to line up"
      description = "The feature needs all of them and reports none of them. The CNI switch, an instance type with more than one network card, and the pod annotation - miss any one and the pod comes up healthy with a single interface"
      value       = "vpc-cni env ${module.eks_vpc_cni_addon.configuration_values}, nodes on ${join(",", var.node_group_instance_types)}, pod annotated=${module.multi_homed_workload.multi_nic_requested}"
    }
    network_card_check_command = {
      order       = 5
      title       = "1. Confirm the instance type has more than one network card"
      description = "MaximumNetworkCards, not MaximumNetworkInterfaces. Every instance type has several interfaces; more than one card is confined to the largest sizes of a few families, and a single-card type gives the pod one interface with nothing reporting why"
      value       = "aws ec2 describe-instance-types --instance-types ${join(" ", var.node_group_instance_types)} --query 'InstanceTypes[].[InstanceType,NetworkInfo.MaximumNetworkCards,NetworkInfo.MaximumNetworkInterfaces]' --output table"
    }
    cni_env_check_command = {
      order       = 6
      title       = "2. Confirm the CNI was told about it"
      description = "What the addon actually pushed into the aws-node DaemonSet. This reads from the cluster rather than from Terraform, which is the point: it is the value the pods on the node are running with"
      value       = "kubectl -n kube-system get daemonset aws-node -o jsonpath='{.spec.template.spec.containers[0].env[?(@.name==\"ENABLE_MULTI_NIC\")]}'"
    }
    rollout_status_command = {
      order       = 7
      title       = "3. Wait for the demo pod"
      description = "Slower than it looks on a multi-NIC cluster: with the feature on the CNI stops allocating addresses in bulk and assigns them on demand, so the first pod on a node waits for an address instead of taking a pre-warmed one"
      value       = module.multi_homed_workload.rollout_status_command
    }
    interface_list_command = {
      order       = 8
      title       = "4. Look inside the pod"
      description = "The whole demo. Two addresses besides loopback means the second network card was used; one means it was not - and that is exactly what a cluster with the feature off, or a node with a single card, also shows"
      value       = module.multi_homed_workload.interface_list_command
    }
    comparison_command = {
      order       = 9
      title       = "5. See the same Deployment without the annotation"
      description = "Re-applies the identical Deployment with the nicConfig annotation removed, which is the honest way to confirm the annotation is what made the difference. Re-apply without the flag to put it back"
      value       = "terraform apply -var multi_homed_annotate=false"
    }
    cni_log_command = {
      order       = 10
      title       = "6. Read the CNI's log if the interface is missing"
      description = "The only place that distinguishes an addon too old to know about ENABLE_MULTI_NIC from an annotation that was never seen. Both look identical from inside the pod"
      value       = module.multi_homed_workload.cni_log_command
    }
    update_kubeconfig_command = {
      order       = 11
      title       = "Re-point kubectl"
      description = "User data already ran this, so kubectl works out of the box. Re-run it if the kubeconfig is ever lost"
      value       = "aws eks update-kubeconfig --region ${data.aws_region.current.region} --name ${module.eks_cluster.cluster_name}"
    }
  }
  # Iterating local.outputs directly would order sections by key. Re-keying by the order field and
  # taking values() - which returns a map's values ordered by key - makes the README read top to
  # bottom while the order stays decided by configuration.
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
# The work happens inside code-server in a browser, where terraform output is not available, so
# every output above is also written to a README in the home directory the IDE opens
# (rules.md H-2).
resource "aws_ssm_association" "vscode_readme" {
  name                             = "AWS-RunShellScript"
  wait_for_success_timeout_seconds = var.readme_timeout_seconds
  targets {
    key    = "InstanceIds"
    values = [module.vscode_ec2.instance_id]
  }
  parameters = {
    # The until loop, not depends_on or wait_for_success_timeout_seconds, is what orders this after
    # the bootstrap (rules.md D-5). The marker path comes back out of the module it was passed into,
    # so it is defined once (rules.md B-5).
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
