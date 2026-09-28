data "aws_region" "current" {}

data "aws_ssm_parameter" "amazon_linux2023_ami_id" {
  name = var.amazon_linux2023_ami_id
}

module "network" {
  source = "./modules/network"
}

module "key_pair" {
  source   = "./modules/key_pair"
  key_name = "${var.prefix}-key"

  # module.network's value references only order this after the specific aws_subnet or
  # aws_vpc that produced them, not after the NAT gateway and route tables the network
  # module also owns. depends_on states "after the whole network" (rules.md D-3).
  depends_on = [module.network]
}

module "eks_cluster" {
  source = "./modules/eks_cluster"

  name               = "stem-cluster"
  kubernetes_version = var.kubernetes_version
  subnet_ids         = concat(module.network.public_subnet_ids, module.network.private_subnet_ids)

  depends_on = [module.network]
}

module "eks_vpc_cni_addon" {
  source = "./modules/eks_vpc_cni_addon"

  cluster_name = module.eks_cluster.cluster_name

  # bootstrap_self_managed_addons = false (modules/eks_cluster) means
  # vpc-cni does not exist until this aws_eks_addon resource creates it. As
  # a DaemonSet it becomes ACTIVE with zero nodes, so it's created before
  # the node group instead of after it (rules.md C-4) - worker nodes need
  # it running to join the cluster in a Ready state.
  depends_on = [module.network, module.eks_cluster]
}

module "eks_kube_proxy_addon" {
  source = "./modules/eks_kube_proxy_addon"

  cluster_name = module.eks_cluster.cluster_name

  # Same reasoning as eks_vpc_cni_addon above: kube-proxy is a DaemonSet
  # and must exist before the node group (rules.md C-4).
  depends_on = [module.network, module.eks_cluster]
}

module "eks_node_group" {
  source = "./modules/eks_node_group"

  cluster_name           = module.eks_cluster.cluster_name
  key_name               = module.key_pair.key_name
  vpc_security_group_ids = [module.eks_cluster.cluster_security_group_id]
  subnet_ids             = module.network.private_subnet_ids

  # Nodes need vpc-cni/kube-proxy running to join the cluster Ready
  # (rules.md C-4).
  depends_on = [module.network, module.eks_vpc_cni_addon, module.eks_kube_proxy_addon]
}

module "eks_coredns_addon" {
  source = "./modules/eks_coredns_addon"

  cluster_name = module.eks_cluster.cluster_name

  # coredns is a Deployment and needs schedulable node capacity to leave
  # its DEGRADED state and become ACTIVE, so it's created after the node
  # group instead of before it (rules.md C-4).
  depends_on = [
  module.network, module.eks_node_group]
}

module "vscode_ec2" {
  source = "./modules/vscode_ec2"

  name          = var.vscode_instance_name
  instance_type = var.vscode_instance_type
  ami_id        = data.aws_ssm_parameter.amazon_linux2023_ami_id.insecure_value
  key_name      = module.key_pair.key_name

  vpc_id    = module.network.vpc_id
  subnet_id = module.network.public_subnet_a_id

  extra_security_group_ids = [module.eks_cluster.cluster_security_group_id]
  aws_region               = data.aws_region.current.region

  marker_file_path = var.marker_file_path

  additional_user_data = <<-EOT
    su - ec2-user << 'EOF'
    export HOME=/home/ec2-user
    cd $HOME
    curl -O https://s3.us-west-2.amazonaws.com/amazon-eks/1.36.2/2026-07-05/bin/linux/amd64/kubectl
    chmod +x ./kubectl
    mkdir -p $HOME/bin && cp ./kubectl $HOME/bin/kubectl && export PATH=$HOME/bin:$PATH
    echo 'export PATH=$HOME/bin:$PATH' >> ~/.bashrc
    echo 'source /usr/share/bash-completion/bash_completion' >> ~/.bashrc
    echo 'source <(kubectl completion bash)' >> ~/.bashrc
    echo 'alias k=kubectl' >>~/.bashrc
    echo 'complete -o default -F __start_kubectl k' >>~/.bashrc

    ARCH=amd64
    PLATFORM=$(uname -s)_$ARCH
    curl -sLO "https://github.com/eksctl-io/eksctl/releases/latest/download/eksctl_$PLATFORM.tar.gz"
    tar -xzf eksctl_$PLATFORM.tar.gz -C /tmp && rm eksctl_$PLATFORM.tar.gz
    sudo install -m 0755 /tmp/eksctl /usr/local/bin && rm /tmp/eksctl

    curl -fsSL -o get_helm.sh https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3
    chmod 700 get_helm.sh
    ./get_helm.sh

    aws eks update-kubeconfig --name ${module.eks_cluster.cluster_name}
    EOF
  EOT

  depends_on = [module.network]
}

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
  # renders them, so no value expression is written twice (rules.md B-5/H-2). Adding an entry here is
  # what makes an output possible, which is what keeps the README from falling behind outputs.tf.
  outputs = {
    vscode = {
      order       = 1
      title       = "code-server"
      description = "Open the IDE here and run every command below from its terminal. kubectl is already installed and the kubeconfig already points at the cluster"
      value       = "http://${module.vscode_ec2.public_ip}:8000"
    }
    eks_cluster_name = {
      order       = 2
      title       = "EKS cluster name"
      description = "Name of the EKS cluster"
      value       = module.eks_cluster.cluster_name
    }
    eks_cluster_endpoint = {
      order       = 3
      title       = "EKS cluster endpoint"
      description = "API server endpoint of the EKS cluster"
      value       = module.eks_cluster.cluster_endpoint
    }
    node_group_name = {
      order       = 4
      title       = "Managed node group"
      description = "The node group this project exists to show. EKS owns the Auto Scaling group behind it, which is why there is no launch template or ASG declared here"
      value       = module.eks_node_group.node_group_name
    }
    nodes_command = {
      order       = 5
      title       = "1. The nodes joined"
      description = "Ready is the state to wait for. A node that stays NotReady is almost always missing vpc-cni or kube-proxy, which is why both addons are created before the node group (rules.md C-4)"
      value       = "kubectl get nodes -o wide"
    }
    node_group_status_command = {
      order       = 6
      title       = "2. The node group is ACTIVE"
      description = "EKS reports the group's own health separately from the nodes'. DEGRADED here names the reason, which a kubectl get nodes cannot"
      value       = "aws eks describe-nodegroup --cluster-name ${module.eks_cluster.cluster_name} --nodegroup-name ${module.eks_node_group.node_group_name} --query 'nodegroup.[status,health]' --output json"
    }
    autoscaling_group_command = {
      order       = 7
      title       = "3. The Auto Scaling group EKS created"
      description = "Not declared anywhere in this configuration - the node group owns it. Scaling it by hand is what the managed group's update path exists to avoid"
      value       = "aws autoscaling describe-auto-scaling-groups --auto-scaling-group-names ${join(" ", module.eks_node_group.autoscaling_group_names)} --query 'AutoScalingGroups[].[AutoScalingGroupName,DesiredCapacity,MinSize,MaxSize]' --output table"
    }
    update_kubeconfig_command = {
      order       = 8
      title       = "Re-point kubectl"
      description = "User data already ran this, so kubectl works out of the box. Re-run it if the kubeconfig is ever lost"
      value       = "aws eks update-kubeconfig --region ${var.aws_region} --name ${module.eks_cluster.cluster_name}"
    }
  }
  # Iterating local.outputs directly would order sections by key. Re-keying by the order field and
  # taking values() sorts by that instead - values() returns a map's values ordered by key - so the
  # README reads in the order the demo is run.
  readme_ordered = values({
    for key, entry in local.outputs : format("%02d-%s", entry.order, key) => entry
  })
  readme_body = join("\n", concat(
    ["# ${var.prefix}", ""],
    flatten([for entry in local.readme_ordered : [
      "## ${entry.title}", "", entry.description, "", "```", entry.value, "```", "",
    ]]),
  ))
}

# The work happens inside code-server in a browser, where "terraform output" does not exist, so every
# output above is also written to a README in the home directory the IDE opens (rules.md H-2). This
# association previously wrote one line - the project title - and left the reader to find the rest.
resource "aws_ssm_association" "vscode_readme" {
  name                             = "AWS-RunShellScript"
  wait_for_success_timeout_seconds = var.readme_timeout_seconds
  targets {
    key    = "InstanceIds"
    values = [module.vscode_ec2.instance_id]
  }
  parameters = {
    # The until loop, not depends_on, is what orders this after the instance bootstrap - the marker is
    # written as the last line of user data (rules.md D-5).
    #
    # SSM runs as root, hence the chown. The heredoc delimiter is quoted and deliberately unlikely to
    # appear in the body: Terraform has already substituted every value, so the shell has no reason to
    # touch a "$" or a backtick in the README - and the commands in it contain both.
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
