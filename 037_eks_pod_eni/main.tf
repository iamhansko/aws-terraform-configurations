module "network" {
  source = "./modules/network"
}

module "key_pair" {
  source = "./modules/key_pair"

  key_name = var.key_name

  # key_pair doesn't reference any network output, so without this the
  # network module's own resources (NAT gateways, routes, etc.) would have
  # no ordering relationship with it at all (rules.md D-2).
  depends_on = [module.network]
}

module "eks_cluster" {
  source = "./modules/eks_cluster"

  name                   = var.cluster_name
  kubernetes_version     = var.kubernetes_version
  subnet_ids             = concat(module.network.public_subnet_ids, module.network.private_subnet_ids)
  endpoint_public_access = var.endpoint_public_access
  public_access_cidrs    = var.public_access_cidrs

  # Referencing module.network.*_subnet_ids only orders this module after
  # the specific subnet resources that produce those outputs, not after
  # every resource in the network module (e.g. NAT gateways, route table
  # associations). depends_on makes "all of network before this" explicit.
  depends_on = [module.network]
}

module "eks_vpc_cni_addon" {
  source = "./modules/eks_vpc_cni_addon"

  cluster_name                      = module.eks_cluster.cluster_name
  enable_pod_eni                    = var.enable_pod_eni
  pod_security_group_enforcing_mode = var.pod_security_group_enforcing_mode

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

  cluster_name   = module.eks_cluster.cluster_name
  instance_types = var.node_group_instance_types
  desired_size   = var.node_group_desired_size
  min_size       = var.node_group_min_size
  max_size       = var.node_group_max_size
  subnet_ids     = module.network.private_subnet_ids

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
  depends_on = [module.eks_node_group]
}

module "pod_security_group_policy" {
  source = "./modules/pod_security_group_policy"

  vpc_id          = module.network.vpc_id
  create_demo_pod = var.create_demo_pod

  # default_sgp/demo_pod (kubectl_manifest) need a live vpc-resource-
  # controller pod, which runs on the node group; ordering the module
  # itself after the node group (not after an unrelated module like
  # eks_coredns_addon) makes `terraform destroy` remove these manifests
  # before the node group disappears (rules.md D-4).
  depends_on = [module.network, module.eks_node_group]
}

module "vscode_ec2" {
  source = "./modules/vscode_ec2"

  vpc_id                      = module.network.vpc_id
  subnet_id                   = module.network.public_subnet_a_id
  key_name                    = module.key_pair.key_name
  instance_type               = var.vscode_instance_type
  allow_inbound_from_anywhere = var.allow_inbound_from_anywhere
  extra_security_group_ids    = [module.eks_cluster.cluster_security_group_id]

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

module "web_ec2" {
  source = "./modules/web_ec2"

  vpc_id        = module.network.vpc_id
  subnet_id     = module.network.private_subnet_b_id
  key_name      = module.key_pair.key_name
  instance_type = var.web_instance_type
  # Keyed by a label rather than passed as a list: the ID is unknown until the
  # pod security group is created, and the module's for_each needs keys that are
  # known during plan (rules.md B-8).
  ingress_source_security_groups = {
    pod = module.pod_security_group_policy.pod_security_group_id
  }

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
