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
# The bucket is plain AWS infrastructure with no Kubernetes in it, so it is its
# own module. Unlike the EBS and EFS projects there is no dynamic provisioning
# here: the storage the pod mounts already exists, which is why what follows is
# a statically provisioned PersistentVolume rather than a StorageClass.
module "s3_bucket" {
  source = "./modules/s3_bucket"

  bucket_prefix = var.bucket_prefix
  force_destroy = var.bucket_force_destroy

  depends_on = [module.network]
}
module "eks_mountpoint_s3_csi_driver_addon" {
  source = "./modules/eks_mountpoint_s3_csi_driver_addon"

  cluster_name      = module.eks_cluster.cluster_name
  oidc_provider_arn = module.eks_cluster.oidc_provider_arn
  oidc_issuer_host  = module.eks_cluster.oidc_issuer_host
  addon_version     = var.mountpoint_s3_csi_driver_addon_version
  # Scoped to this one bucket rather than every bucket in the account. The ARN
  # is injected, so the module never looks the bucket up itself (rules.md B-6).
  bucket_arns  = [module.s3_bucket.bucket_arn]
  allow_delete = var.allow_delete

  # The driver runs as a DaemonSet, so it would reach ACTIVE with zero nodes,
  # but its whole purpose is mounting volumes into pods - ordering it after the
  # node group also means terraform destroy removes it after the workloads that
  # depend on it (rules.md C-4).
  depends_on = [module.network, module.eks_node_group, module.s3_bucket]
}
module "s3_mountpoint_volume" {
  source = "./modules/s3_mountpoint_volume"

  namespace = "default"
  # Driver name from the addon module, bucket name from the bucket module, and
  # allow-delete from the same switch that granted s3:DeleteObject, rather than
  # restating any of them here (rules.md B-5).
  driver          = module.eks_mountpoint_s3_csi_driver_addon.driver
  bucket_name     = module.s3_bucket.bucket_name
  allow_delete    = module.eks_mountpoint_s3_csi_driver_addon.allow_delete
  region          = data.aws_region.current.region
  prefix          = var.mount_prefix
  volume_capacity = var.volume_capacity
  create_demo_pod = var.create_demo_pod

  # These are kubectl_manifest resources talking straight to the cluster's API
  # server, and the mount is performed by the driver's DaemonSet pod on the node
  # running the demo pod. Ordering the module after both the addon and the node
  # group makes terraform destroy delete the pod and claim - letting the driver
  # unmount cleanly - before either disappears (rules.md D-4).
  depends_on = [module.network, module.eks_node_group, module.eks_mountpoint_s3_csi_driver_addon, module.s3_bucket]
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
  # (rules.md H-1). None of them is used to create resources - that stays with
  # the kubectl provider (rules.md E-1).
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
  # Every output this project exposes, defined once. outputs.tf projects these
  # and the README below renders them, so no value is written twice (rules.md
  # #5/#35). Adding an entry here is what makes an output possible, which is
  # what keeps the README from silently falling behind outputs.tf.
  outputs = {
    vscode_url = {
      order       = 1
      title       = "code-server"
      description = "Open the IDE here. The rest of these commands are meant to be run from its terminal"
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
      description = "API server endpoint of the EKS cluster"
      value       = module.eks_cluster.cluster_endpoint
    }
    bucket_name = {
      order       = 4
      title       = "S3 bucket"
      description = "Bucket mounted into the pod. The name is generated from a prefix because bucket names are globally unique"
      value       = module.s3_bucket.bucket_name
    }
    driver_role_arn = {
      order       = 5
      title       = "Mountpoint driver IAM role"
      description = "Role the driver assumes through IRSA. Its policy is scoped to the bucket above, so a pod mounting a volume can reach that bucket and nothing else"
      value       = module.eks_mountpoint_s3_csi_driver_addon.driver_role_arn
    }
    persistent_volume_name = {
      order       = 6
      title       = "PersistentVolume"
      description = "Statically provisioned volume backed by the bucket. Mountpoint has no dynamic provisioning, so there is no StorageClass here"
      value       = module.s3_mountpoint_volume.persistent_volume_name
    }
    claim_name = {
      order       = 7
      title       = "PersistentVolumeClaim"
      description = "Claim pre-bound to that volume, which the demo pod mounts"
      value       = module.s3_mountpoint_volume.claim_name
    }
    mount_options = {
      order       = 8
      title       = "Mountpoint mount options"
      description = "Options the volume was mounted with. region is mandatory, and allow-delete only appears when the driver's IAM policy also grants s3:DeleteObject"
      value       = join(",", module.s3_mountpoint_volume.mount_options)
    }
    demo_pod_files_command = {
      order       = 9
      title       = "1. List the mount from inside the pod"
      description = "Shows the file the demo pod wrote, as seen through the Mountpoint filesystem"
      value       = module.s3_mountpoint_volume.demo_pod_files_command
    }
    bucket_objects_command = {
      order       = 10
      title       = "2. List the same objects through the S3 API"
      description = "The same file as a real S3 object under the mount prefix, which is what shows the write went to the bucket rather than to a container filesystem"
      value       = module.s3_mountpoint_volume.bucket_objects_command
    }
  }
  # Iterating local.outputs directly would order sections by key, which puts
  # "2. List the same objects" above "1. List the mount". Re-keying by the order
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
