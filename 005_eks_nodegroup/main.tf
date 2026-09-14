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
  # the node group instead of after it (rules.md #28) - worker nodes need
  # it running to join the cluster in a Ready state.
  depends_on = [module.network, module.eks_cluster]
}

module "eks_kube_proxy_addon" {
  source = "./modules/eks_kube_proxy_addon"

  cluster_name = module.eks_cluster.cluster_name

  # Same reasoning as eks_vpc_cni_addon above: kube-proxy is a DaemonSet
  # and must exist before the node group (rules.md #28).
  depends_on = [module.network, module.eks_cluster]
}

module "eks_node_group" {
  source = "./modules/eks_node_group"

  cluster_name           = module.eks_cluster.cluster_name
  key_name               = module.key_pair.key_name
  vpc_security_group_ids = [module.eks_cluster.cluster_security_group_id]
  subnet_ids             = module.network.private_subnet_ids

  # Nodes need vpc-cni/kube-proxy running to join the cluster Ready
  # (rules.md #28).
  depends_on = [module.network, module.eks_vpc_cni_addon, module.eks_kube_proxy_addon]
}

module "eks_coredns_addon" {
  source = "./modules/eks_coredns_addon"

  cluster_name = module.eks_cluster.cluster_name

  # coredns is a Deployment and needs schedulable node capacity to leave
  # its DEGRADED state and become ACTIVE, so it's created after the node
  # group instead of before it (rules.md #28).
  depends_on = [module.eks_node_group]
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

resource "aws_ssm_association" "vscode_readme" {
  name                             = "AWS-RunShellScript"
  wait_for_success_timeout_seconds = 300
  targets {
    key    = "InstanceIds"
    values = [module.vscode_ec2.instance_id]
  }
  parameters = {
    commands = <<-EOT
      until [ -f ${module.vscode_ec2.marker_file_path}/userdata ]; do sleep 10; done
      echo '# EKS Managed Node Group' > /home/ec2-user/README.md
      EOT
  }
}
