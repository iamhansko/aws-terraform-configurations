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

  name               = "${var.prefix}-eks-cluster"
  kubernetes_version = var.kubernetes_version
  subnet_ids = concat(
    [module.network.public_subnet_a_id, module.network.public_subnet_b_id],
    module.network.private_subnet_ids,
  )

  depends_on = [module.network]
}

module "eks_vpc_cni_addon" {
  source = "./modules/eks_vpc_cni_addon"

  cluster_name = module.eks_cluster.cluster_name

  # vpc-cni is a DaemonSet and becomes ACTIVE with zero nodes, so it only
  # needs the cluster (rules.md #28) and is created before any node
  # capacity (eks_fargate_profile/karpenter) exists.
  depends_on = [module.eks_cluster]
}

module "eks_kube_proxy_addon" {
  source = "./modules/eks_kube_proxy_addon"

  cluster_name = module.eks_cluster.cluster_name

  # kube-proxy is a DaemonSet and becomes ACTIVE with zero nodes, so it
  # only needs the cluster (rules.md #28) and is created before any node
  # capacity (eks_fargate_profile/karpenter) exists.
  depends_on = [module.eks_cluster]
}

module "eks_fargate_profile" {
  source = "./modules/eks_fargate_profile"

  cluster_name = module.eks_cluster.cluster_name
  profile_name = "${var.prefix}-kubesystem-fargate-profile"
  subnet_ids   = module.network.private_subnet_ids
  namespace    = "kube-system"

  # vpc-cni/kube-proxy must be running before workloads (including
  # coredns, once it's scheduled onto this profile) can rely on pod
  # networking (rules.md #28).
  depends_on = [module.eks_vpc_cni_addon, module.eks_kube_proxy_addon]
}

module "eks_coredns_addon" {
  source = "./modules/eks_coredns_addon"

  cluster_name = module.eks_cluster.cluster_name

  # coredns is a Deployment and needs schedulable capacity to leave
  # DEGRADED and become ACTIVE; that capacity is the kube-system Fargate
  # profile, which must exist first (rules.md #28).
  depends_on = [module.eks_fargate_profile]
}

module "karpenter" {
  source = "./modules/karpenter"

  cluster_name      = module.eks_cluster.cluster_name
  oidc_provider_arn = module.eks_cluster.oidc_provider_arn
  oidc_issuer_host  = module.eks_cluster.oidc_issuer_host

  # The Karpenter controller pod needs coredns ACTIVE to resolve DNS and
  # reach the EKS API (rules.md #22, #28).
  depends_on = [module.eks_coredns_addon]
}

module "vscode_ec2" {
  source = "./modules/vscode_ec2"

  name          = "vscode"
  instance_type = var.vscode_instance_type
  ami_id        = data.aws_ssm_parameter.amazon_linux2023_ami_id.insecure_value
  key_name      = module.key_pair.key_name

  vpc_id    = module.network.vpc_id
  subnet_id = module.network.public_subnet_a_id

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

resource "aws_vpc_security_group_ingress_rule" "vscode_ec2_security_group_ingress" {
  security_group_id            = module.eks_cluster.cluster_security_group_id
  ip_protocol                  = "-1"
  referenced_security_group_id = module.vscode_ec2.security_group_id
}

resource "aws_eks_access_entry" "vscode_ec2_iam_access_entry" {
  cluster_name  = module.eks_cluster.cluster_name
  principal_arn = module.vscode_ec2.iam_role_arn
  type          = "STANDARD"
}

resource "aws_eks_access_policy_association" "vscode_ec2_iam_access_policy_association" {
  cluster_name  = module.eks_cluster.cluster_name
  principal_arn = module.vscode_ec2.iam_role_arn
  policy_arn    = "arn:aws:eks::aws:cluster-access-policy/AmazonEKSClusterAdminPolicy"
  access_scope {
    type = "cluster"
  }

  depends_on = [aws_eks_access_entry.vscode_ec2_iam_access_entry]
}

module "batch" {
  source = "./modules/batch"

  cluster_name                     = module.eks_cluster.cluster_name
  cluster_arn                      = module.eks_cluster.cluster_arn
  kubernetes_namespace             = "batch-default"
  additional_kubernetes_namespaces = ["batch-app"]
  subnet_ids                       = module.network.private_subnet_ids
  security_group_ids               = [module.eks_cluster.cluster_security_group_id]
  key_name                         = module.key_pair.key_name
  name_prefix                      = var.prefix
}
