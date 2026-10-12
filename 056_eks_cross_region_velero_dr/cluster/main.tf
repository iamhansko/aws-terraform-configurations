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
  # The load balancer controller finds where to put a load balancer by these tags, and the
  # _monolithic template tagged no subnets at all - so the demo Service would have failed with
  # "couldn't auto-discover subnets" even once the controller was installed (rules.md G-1).
  public_subnet_tags  = var.public_subnet_tags
  private_subnet_tags = var.private_subnet_tags
}
module "key_pair" {
  source = "./modules/key_pair"

  key_name = var.key_name

  # key_pair consumes no network output, so nothing would otherwise order it against the network
  # module's resources. Every module in a root that has a network module waits for all of it
  # (rules.md D-3).
  depends_on = [module.network]
}
# One bucket for both clusters, as the _monolithic template had it, and that is the point of this
# variant: the restoring cluster reads the backup out of the same bucket the backing-up cluster wrote
# it to, with nothing between them. The cross-account variants replace that shared bucket with two
# and S3 replication.
module "velero_backup_bucket" {
  source = "./modules/velero_backup_bucket"

  bucket_name        = var.backup_bucket_name
  bucket_name_prefix = "${var.prefix}-velero-"
  force_destroy      = var.backup_bucket_force_destroy

  depends_on = [module.network]
}
# ---------------------------------------------------------------------------------------------------
# Primary cluster - the one the backup is taken from
# ---------------------------------------------------------------------------------------------------
module "primary_eks_cluster" {
  source = "./modules/eks_cluster"

  name                   = var.primary_cluster_name
  kubernetes_version     = var.kubernetes_version
  subnet_ids             = concat(module.network.public_subnet_ids, module.network.private_subnet_ids)
  endpoint_public_access = var.endpoint_public_access
  public_access_cidrs    = var.public_access_cidrs

  # Referencing module.network.*_subnet_ids only orders this after the specific aws_subnet resources
  # behind those outputs, not after the NAT gateways and route table associations that never surface
  # as outputs (rules.md D-3).
  depends_on = [module.network]
}
module "primary_eks_vpc_cni_addon" {
  source = "./modules/eks_vpc_cni_addon"

  cluster_name = module.primary_eks_cluster.cluster_name

  # bootstrap_self_managed_addons = false on the cluster means vpc-cni does not exist until this addon
  # creates it. As a DaemonSet it reaches ACTIVE with zero nodes, so it comes before any capacity -
  # and nodes need it to join Ready (rules.md C-4). It is also what makes the demo Service's
  # target-type ip work, by making pod addresses routable in the VPC (rules.md G-1).
  depends_on = [module.network, module.primary_eks_cluster]
}
module "primary_eks_kube_proxy_addon" {
  source = "./modules/eks_kube_proxy_addon"

  cluster_name = module.primary_eks_cluster.cluster_name

  # Same reasoning as the vpc-cni addon (rules.md C-4).
  depends_on = [module.network, module.primary_eks_cluster]
}
# The credential mechanism every controller in this project uses. A DaemonSet, so it reaches ACTIVE
# with zero nodes (rules.md C-4) - but it has to exist before the load balancer controller, the EBS
# CSI driver or Velero start, because without the agent on the node their pods get no credentials at
# all and log an AccessDenied loop rather than failing.
module "primary_eks_pod_identity_agent_addon" {
  source = "./modules/eks_pod_identity_agent_addon"

  cluster_name = module.primary_eks_cluster.cluster_name

  depends_on = [module.network, module.primary_eks_cluster]
}
module "primary_eks_node_group" {
  source = "./modules/eks_node_group"

  cluster_name    = module.primary_eks_cluster.cluster_name
  node_group_name = var.node_group_name
  instance_types  = var.node_group_instance_types
  desired_size    = var.node_group_desired_size
  min_size        = var.node_group_min_size
  max_size        = var.node_group_max_size
  subnet_ids      = module.network.private_subnet_ids
  key_name        = module.key_pair.key_name

  # Nodes need vpc-cni and kube-proxy running to join the cluster Ready (rules.md C-4).
  depends_on = [
    module.network,
    module.primary_eks_vpc_cni_addon,
    module.primary_eks_kube_proxy_addon,
  ]
}
module "primary_eks_coredns_addon" {
  source = "./modules/eks_coredns_addon"

  cluster_name = module.primary_eks_cluster.cluster_name

  # coredns is a Deployment and needs schedulable capacity to leave DEGRADED and become ACTIVE
  # (rules.md C-4).
  depends_on = [
  module.network, module.primary_eks_node_group]
}
# The driver that provisions the demo's volumes. Without it the StatefulSet's claims stay Pending,
# the pods never start, and Velero backs up a workload with no data in it - which reports as success.
module "primary_eks_ebs_csi_driver_addon" {
  source = "./modules/eks_ebs_csi_driver_addon"

  cluster_name     = module.primary_eks_cluster.cluster_name
  role_name_prefix = "${var.prefix}-primary-ebs-csi-"

  # The addon's own pod_identity_association needs the agent already installed, and its controller is
  # a Deployment so it needs schedulable capacity (rules.md C-4/D-2).
  depends_on = [
    module.network,
    module.primary_eks_pod_identity_agent_addon,
    module.primary_eks_node_group,
  ]
}
# The CSI snapshot controller, which is what turns a VolumeSnapshot object into a driver call. Velero's
# EnableCSI feature depends on it; without it a backup produces snapshots stuck Pending and no volume
# data. The _monolithic template installed it with two unpinned "kubectl kustomize <github url>"
# commands (see the module).
module "primary_eks_snapshot_controller_addon" {
  source = "./modules/eks_snapshot_controller_addon"

  cluster_name = module.primary_eks_cluster.cluster_name

  # A Deployment, so it needs schedulable capacity (rules.md C-4).
  depends_on = [
  module.network, module.primary_eks_node_group]
}
module "primary_aws_load_balancer_controller" {
  source    = "./modules/aws_load_balancer_controller"
  providers = { helm = helm.primary }

  # The cluster this controller belongs to. The _monolithic template installed the controller twice
  # and passed the primary cluster's name both times, so the secondary cluster's controller tagged its
  # load balancers as belonging to the primary and reconciled load balancers that were not its own -
  # with no error anywhere (rules.md G-3).
  cluster_name                   = module.primary_eks_cluster.cluster_name
  vpc_id                         = module.network.vpc_id
  aws_region                     = data.aws_region.current.region
  role_name_prefix               = "${var.prefix}-primary-lbc-"
  chart_version                  = var.aws_load_balancer_controller_chart_version
  enable_service_mutator_webhook = var.enable_service_mutator_webhook

  # The controller pod needs schedulable capacity, working cluster DNS and the pod identity agent
  # before it can reach the AWS API, and wait = true on its Helm release would otherwise time out
  # (rules.md D-2).
  depends_on = [
    module.network,
    module.primary_eks_node_group,
    module.primary_eks_coredns_addon,
    module.primary_eks_pod_identity_agent_addon,
  ]
}
module "primary_csi_storage_classes" {
  source    = "./modules/csi_storage_classes"
  providers = { kubectl = kubectl.primary }

  # The VolumeSnapshotClass instantiates a CRD the snapshot-controller addon installs, and the
  # StorageClass is useless without the EBS CSI driver. Neither is expressed by a value reference
  # (rules.md D-2/E-2).
  depends_on = [
    module.network,
    module.primary_eks_snapshot_controller_addon,
    module.primary_eks_ebs_csi_driver_addon,
    module.primary_eks_coredns_addon,
  ]
}
module "primary_velero" {
  source    = "./modules/velero"
  providers = { helm = helm.primary }

  cluster_name     = module.primary_eks_cluster.cluster_name
  role_name_prefix = "${var.prefix}-primary-velero-"
  bucket_name      = module.velero_backup_bucket.bucket_name
  bucket_arn       = module.velero_backup_bucket.bucket_arn
  # The bucket's own region and the cluster's region. Equal in this variant because everything shares
  # one region - which is exactly why the _monolithic template could pass the same value to both
  # without noticing they are different things (rules.md I-3).
  bucket_region    = module.velero_backup_bucket.bucket_region
  snapshot_region  = data.aws_region.current.region
  chart_version    = var.velero_chart_version
  plugin_image_tag = var.velero_plugin_image_tag

  # Velero's CSI support needs the snapshot CRDs and a snapshot class to exist, and its Deployment
  # needs schedulable capacity and DNS. Ordering the module after the storage classes also means
  # terraform destroy removes Velero after them, so it is still running when its own objects go
  # (rules.md D-2/D-4).
  depends_on = [
    module.network,
    module.primary_eks_node_group,
    module.primary_eks_coredns_addon,
    module.primary_eks_pod_identity_agent_addon,
    module.primary_csi_storage_classes,
  ]
}
# The workload the backup is taken of. Only on the primary cluster: the secondary receives it through
# a restore, which is the whole demonstration.
module "primary_stateful_workload" {
  source    = "./modules/stateful_workload"
  providers = { kubectl = kubectl.primary }

  name      = var.workload_name
  namespace = var.workload_namespace
  replicas  = var.workload_replicas
  image     = var.workload_image
  # The class the storage module created, not a restatement of its name. A claim naming a class that
  # does not exist stays Pending and the StatefulSet says nothing about why (rules.md B-5).
  storage_class_name = module.primary_csi_storage_classes.storage_class_name
  volume_size        = var.workload_volume_size

  # The claims need the EBS CSI driver and the StorageClass; the Service needs the load balancer
  # controller to be reconciling, or the in-tree provider claims it and builds a Classic Load
  # Balancer instead (rules.md G-1). Ordering the module after the controller also makes terraform
  # destroy delete the Service while the controller is still alive, so the load balancer is cleaned up
  # rather than orphaned (rules.md D-4).
  depends_on = [
    module.network,
    module.primary_csi_storage_classes,
    module.primary_aws_load_balancer_controller,
  ]
}
# ---------------------------------------------------------------------------------------------------
# Secondary cluster - the one the backup is restored into
#
# Everything the primary has except the workload. The restore creates that, which is the point: the
# StatefulSet, its claims and the data in its volumes all arrive from the backup rather than from this
# configuration.
# ---------------------------------------------------------------------------------------------------
module "secondary_eks_cluster" {
  source = "./modules/eks_cluster"

  name                   = var.secondary_cluster_name
  kubernetes_version     = var.kubernetes_version
  subnet_ids             = concat(module.network.public_subnet_ids, module.network.private_subnet_ids)
  endpoint_public_access = var.endpoint_public_access
  public_access_cidrs    = var.public_access_cidrs

  depends_on = [module.network]
}
module "secondary_eks_vpc_cni_addon" {
  source = "./modules/eks_vpc_cni_addon"

  cluster_name = module.secondary_eks_cluster.cluster_name

  depends_on = [module.network, module.secondary_eks_cluster]
}
module "secondary_eks_kube_proxy_addon" {
  source = "./modules/eks_kube_proxy_addon"

  cluster_name = module.secondary_eks_cluster.cluster_name

  depends_on = [module.network, module.secondary_eks_cluster]
}
module "secondary_eks_pod_identity_agent_addon" {
  source = "./modules/eks_pod_identity_agent_addon"

  cluster_name = module.secondary_eks_cluster.cluster_name

  depends_on = [module.network, module.secondary_eks_cluster]
}
module "secondary_eks_node_group" {
  source = "./modules/eks_node_group"

  cluster_name    = module.secondary_eks_cluster.cluster_name
  node_group_name = var.node_group_name
  instance_types  = var.node_group_instance_types
  desired_size    = var.node_group_desired_size
  min_size        = var.node_group_min_size
  max_size        = var.node_group_max_size
  subnet_ids      = module.network.private_subnet_ids
  key_name        = module.key_pair.key_name

  depends_on = [
    module.network,
    module.secondary_eks_vpc_cni_addon,
    module.secondary_eks_kube_proxy_addon,
  ]
}
module "secondary_eks_coredns_addon" {
  source = "./modules/eks_coredns_addon"

  cluster_name = module.secondary_eks_cluster.cluster_name

  depends_on = [
  module.network, module.secondary_eks_node_group]
}
# The driver on the restoring side, and the reason a restore produces a working volume rather than a
# Pending claim: the snapshot in the backup has to be turned back into an EBS volume here.
module "secondary_eks_ebs_csi_driver_addon" {
  source = "./modules/eks_ebs_csi_driver_addon"

  cluster_name     = module.secondary_eks_cluster.cluster_name
  role_name_prefix = "${var.prefix}-secondary-ebs-csi-"

  depends_on = [
    module.network,
    module.secondary_eks_pod_identity_agent_addon,
    module.secondary_eks_node_group,
  ]
}
module "secondary_eks_snapshot_controller_addon" {
  source = "./modules/eks_snapshot_controller_addon"

  cluster_name = module.secondary_eks_cluster.cluster_name

  depends_on = [
  module.network, module.secondary_eks_node_group]
}
module "secondary_aws_load_balancer_controller" {
  source    = "./modules/aws_load_balancer_controller"
  providers = { helm = helm.secondary }

  # The secondary cluster's own name. This one line is the _monolithic template's bug: its second
  # helm install passed the primary cluster's name here (rules.md G-3).
  cluster_name                   = module.secondary_eks_cluster.cluster_name
  vpc_id                         = module.network.vpc_id
  aws_region                     = data.aws_region.current.region
  role_name_prefix               = "${var.prefix}-secondary-lbc-"
  chart_version                  = var.aws_load_balancer_controller_chart_version
  enable_service_mutator_webhook = var.enable_service_mutator_webhook

  depends_on = [
    module.network,
    module.secondary_eks_node_group,
    module.secondary_eks_coredns_addon,
    module.secondary_eks_pod_identity_agent_addon,
  ]
}
# The same classes on the restoring side, and they have to exist before the restore rather than after:
# a restored PersistentVolumeClaim names its StorageClass, and a claim naming a class this cluster does
# not have stays Pending. Velero does not create StorageClasses unless they were in the backup, and the
# _monolithic template's backup covered only the default namespace.
module "secondary_csi_storage_classes" {
  source    = "./modules/csi_storage_classes"
  providers = { kubectl = kubectl.secondary }

  depends_on = [
    module.network,
    module.secondary_eks_snapshot_controller_addon,
    module.secondary_eks_ebs_csi_driver_addon,
    module.secondary_eks_coredns_addon,
  ]
}
# Velero on the restoring side, pointed at the same bucket. Its BackupStorageLocation is what syncs the
# primary's backups into this cluster - a restore cannot name a backup this Velero has not seen, which
# is why both installations read one bucket in this variant.
module "secondary_velero" {
  source    = "./modules/velero"
  providers = { helm = helm.secondary }

  cluster_name     = module.secondary_eks_cluster.cluster_name
  role_name_prefix = "${var.prefix}-secondary-velero-"
  bucket_name      = module.velero_backup_bucket.bucket_name
  bucket_arn       = module.velero_backup_bucket.bucket_arn
  bucket_region    = module.velero_backup_bucket.bucket_region
  snapshot_region  = data.aws_region.current.region
  chart_version    = var.velero_chart_version
  plugin_image_tag = var.velero_plugin_image_tag

  depends_on = [
    module.network,
    module.secondary_eks_node_group,
    module.secondary_eks_coredns_addon,
    module.secondary_eks_pod_identity_agent_addon,
    module.secondary_csi_storage_classes,
  ]
}
# ---------------------------------------------------------------------------------------------------
# Workbench
# ---------------------------------------------------------------------------------------------------
module "vscode_ec2" {
  source = "./modules/vscode_ec2"

  vpc_id                      = module.network.vpc_id
  subnet_id                   = module.network.public_subnet_a_id
  key_name                    = module.key_pair.key_name
  instance_type               = var.vscode_instance_type
  allow_inbound_from_anywhere = var.allow_inbound_from_anywhere
  marker_file_path            = var.marker_file_path
  # Both clusters' security groups, so the instance can reach either API server. The module is handed
  # an ID list and never learns what they belong to (rules.md B-6).
  extra_security_group_ids = [
    module.primary_eks_cluster.cluster_security_group_id,
    module.secondary_eks_cluster.cluster_security_group_id,
  ]

  # An EKS cluster and this instance share a root module, so it is the workbench for those clusters and
  # carries all five tools (rules.md H-1). None of them creates anything: Velero, the controllers, the
  # storage classes and the workload that the _monolithic template installed from here are Terraform
  # resources now (rules.md E-1). The velero CLI stays because taking a backup and running a restore is
  # the demo, and that is deliberately a manual act rather than something an apply does.
  #
  # Three bugs from that template are fixed rather than carried over. It ran "exec bash" partway
  # through the user data, which replaces the shell and discards every line after it - eksctl, helm,
  # every manifest, both helm installs and the whole Velero setup were below that line, so the project
  # never did anything at all. It pulled eksctl from weaveworks; eksctl-io is the project's own org
  # (rules.md H-1). And it wrote "complete -o default -F __start_kubectl k" into .bashrc before the
  # line that sources kubectl's completion, so every login printed a "function not found" error.
  #
  # The two kubeconfig contexts are set up with the same --alias names the original used, because the
  # demo's commands switch between them.
  additional_user_data = <<-EOT
    dnf install -yq docker
    systemctl enable --now docker
    usermod -aG docker ec2-user
    # code-server is already running and predates the docker group, so its terminals would not have it
    # without a restart.
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
    curl -fsSL -o get_helm.sh https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3
    chmod 700 get_helm.sh
    ./get_helm.sh
    # The velero CLI, for taking backups and restores by hand. The server side is a Helm release, so
    # this is not what installs Velero - it only talks to it.
    curl -sL -o velero.tar.gz https://github.com/vmware-tanzu/velero/releases/download/${var.velero_cli_version}/velero-${var.velero_cli_version}-linux-amd64.tar.gz
    tar -xzf velero.tar.gz
    sudo install -m 0755 velero-${var.velero_cli_version}-linux-amd64/velero /usr/local/bin/velero
    rm -r velero.tar.gz velero-${var.velero_cli_version}-linux-amd64
    echo 'source <(velero completion bash)' >> ~/.bashrc
    aws configure set default.region ${data.aws_region.current.region}
    # Two contexts, named the way the demo's commands expect.
    aws eks update-kubeconfig --region ${data.aws_region.current.region} --name ${module.primary_eks_cluster.cluster_name} --alias primary
    aws eks update-kubeconfig --region ${data.aws_region.current.region} --name ${module.secondary_eks_cluster.cluster_name} --alias secondary
    kubectl config use-context primary
    EOF
  EOT

  depends_on = [module.network]
}
# Granting the workbench's instance role access to both clusters joins modules that know nothing about
# each other, so it belongs in the root (rules.md C-1). for_each over a static map of labels, so the
# keys are known at plan time even though the cluster names are not (rules.md B-8).
locals {
  cluster_names = {
    primary   = module.primary_eks_cluster.cluster_name
    secondary = module.secondary_eks_cluster.cluster_name
  }
}
resource "aws_eks_access_entry" "vscode_access_entry" {
  for_each = local.cluster_names

  cluster_name  = each.value
  principal_arn = module.vscode_ec2.iam_role_arn
  type          = "STANDARD"
}
resource "aws_eks_access_policy_association" "vscode_access_policy_association" {
  for_each = local.cluster_names

  cluster_name  = each.value
  principal_arn = module.vscode_ec2.iam_role_arn
  policy_arn    = "arn:aws:eks::aws:cluster-access-policy/AmazonEKSClusterAdminPolicy"
  access_scope {
    type = "cluster"
  }

  depends_on = [aws_eks_access_entry.vscode_access_entry]
}
# Writes the test line into every pod's volume on the primary cluster.
#
# Without it the workload answers 403. The claim is mounted over the directory nginx serves and a new
# volume is empty, so there is no index.html to return, and each pod logs
#
#   directory index of "/usr/share/nginx/html/" is forbidden
#
# Each pod has its own volume, so every pod needs its own write - the commands are the stateful_workload
# module's write_test_data_commands, one per replica, run exactly as the README prints them for pod 0
# (rules.md B-5). With the default of two replicas that is web-0 and web-1.
#
# An SSM association rather than a Terraform resource because nothing in the kubectl or helm provider
# can exec into a pod. rules.md E-1 keeps Kubernetes resources out of shell scripts, and this creates none:
# it writes a file into a volume that already exists. It runs on the workbench because that is where
# kubectl and both kubeconfig contexts are (rules.md H-1), and as ec2-user because the tools and the
# kubeconfig live in that user's home, not root's.
#
# Unlike the backup and the restore, which are deliberately left as manual acts, this one is the apply's:
# it is what makes the workload serve at all, not a step of the demo.
#
# Primary only. The secondary's volumes come from the restore, and writing there would replace the
# restored data with a fresh line - the one thing the demo exists to show arriving from the backup.
# That is also why the script pins --context primary rather than trusting the current context, which the
# demo's own commands switch to secondary: an association that re-ran at that moment would otherwise
# write into the restored cluster. The module's command strings do not name a context, because the
# README runs the same strings against both clusters, so the pin is a function that wraps kubectl for
# this script only. It changes nothing in the user's kubeconfig.
#
# The rollout wait is the script's own, not Terraform's: kubectl_manifest returns when the API server
# accepts a StatefulSet, long before its pods exist, and kubectl exec on a pod that is not there fails
# (rules.md E-9). The until loop, not depends_on, orders this after the instance bootstrap, and the
# marker it leaves lets a later step wait for it (rules.md D-5).
#
# wait_for_success_timeout_seconds is set so that a failed write fails the apply. Left out, the apply
# would finish cleanly and the 403 would be the only sign anything went wrong.
resource "aws_ssm_association" "primary_test_data" {
  name                             = "AWS-RunShellScript"
  wait_for_success_timeout_seconds = var.test_data_timeout_seconds
  targets {
    key    = "InstanceIds"
    values = [module.vscode_ec2.instance_id]
  }
  parameters = {
    # The nested heredoc works because <<-EOT strips indentation based on the template source lines
    # only: the second and later lines of the interpolated command list sit at column 0, and so does
    # TFSTEP once the stripping is done. A .tf saved with CRLF would make the terminator "TFSTEP\r" and
    # not one line of this would run (rules.md A-4).
    commands = <<-EOT
      set -euo pipefail
      until [ -f ${module.vscode_ec2.marker_file_path}/userdata ]; do sleep 10; done
      sudo -Eu ec2-user bash << 'TFSTEP'
      set -euo pipefail
      export HOME=/home/ec2-user
      export PATH=/home/ec2-user/bin:$PATH
      kubectl() { command kubectl --context primary "$@"; }
      ${module.primary_stateful_workload.rollout_status_command}
      ${join("\n", module.primary_stateful_workload.write_test_data_commands)}
      TFSTEP
      touch ${module.vscode_ec2.marker_file_path}/primary_test_data
      EOT
  }

  # The StatefulSet has to exist for the rollout wait to find it, and the access entry is what lets
  # kubectl authenticate to the cluster at all. The command strings come from module outputs that read
  # only variables, so referencing them orders nothing by itself (rules.md D-2).
  depends_on = [
    module.primary_stateful_workload,
    aws_eks_access_policy_association.vscode_access_policy_association,
  ]
}
locals {
  # Every output this project exposes, defined once. outputs.tf projects these and the README below
  # renders them, so no value expression is written twice (rules.md B-5/H-2). Adding an entry here is
  # what makes an output possible, which is what keeps the README from falling behind outputs.tf.
  outputs = {
    vscode_url = {
      order       = 1
      title       = "code-server"
      description = "Open the IDE here. Every command below is meant to be run from its terminal, where kubectl, helm, eksctl and the velero CLI are installed and both cluster contexts are already configured"
      value       = module.vscode_ec2.vscode_url
    }
    what_this_variant_is = {
      order       = 2
      title       = "What this variant is"
      description = "Two clusters in one account and one region, sharing a VPC and one backup bucket. The region boundary that gives the project its name is in the primary_account and secondary_account roots; this is the rehearsal, where everything except that boundary is real - two Velero installations, a volume with data in it, and a restore that has to rebuild that volume in a cluster that never saw it"
      value       = "primary: ${module.primary_eks_cluster.cluster_name} | secondary: ${module.secondary_eks_cluster.cluster_name} | region: ${data.aws_region.current.region} | bucket: ${module.velero_backup_bucket.bucket_name}"
    }
    backup_bucket_name = {
      order       = 3
      title       = "Backup bucket"
      description = "One bucket both Velero installations read and write. That shared bucket is what lets the secondary cluster see the primary's backups with no replication in between - and it is what the cross-region variants replace with two buckets and S3 replication"
      value       = module.velero_backup_bucket.bucket_name
    }
    velero_status_command = {
      order       = 4
      title       = "1. Confirm Velero is healthy on both clusters"
      description = "Run it for each context. The BackupStorageLocation must say Available: Unavailable means the plugin image is missing, the bucket region is wrong, or the Pod Identity association is not being used - and a backup taken against an Unavailable location fails immediately rather than silently"
      value       = "kubectl config use-context primary && ${module.primary_velero.backup_location_check_command} ; kubectl config use-context secondary && ${module.secondary_velero.backup_location_check_command}"
    }
    node_agent_check_command = {
      order       = 5
      title       = "2. Confirm the node agent is running"
      description = "The node agent is what moves snapshot data into the bucket. Without it a backup taken with --snapshot-move-data completes having recorded only that an EBS snapshot exists in this region, so there is nothing in the bucket for the other cluster to restore from - and the backup still reports Completed"
      value       = module.primary_velero.status_command
    }
    snapshot_class_check_command = {
      order       = 6
      title       = "3. Confirm the snapshot class carries the Velero label"
      description = "Velero picks a VolumeSnapshotClass by the velero.io/csi-volumesnapshot-class label, not by the default annotation. Missing it means Velero skips the volume entirely and reports the backup as Completed - the quietest failure in this project, which is why this check comes before taking a backup"
      value       = module.primary_csi_storage_classes.snapshot_class_check_command
    }
    workload_volume_check_command = {
      order       = 7
      title       = "4. Confirm the workload's volumes are bound"
      description = "One claim per pod, each Bound. A claim stuck Pending is the EBS CSI driver or a StorageClass name that does not exist - and with WaitForFirstConsumer binding it stays Pending until its pod is scheduled, which is normal for seconds and a problem after a minute"
      value       = "kubectl config use-context primary && ${module.primary_stateful_workload.volume_check_command}"
    }
    write_test_data_command = {
      order       = 8
      title       = "5. Put a fresh line in the volume"
      description = "Optional: the apply has already done this once. An SSM association on this instance waited for the StatefulSet to roll out, then wrote a 'hello from <pod> at <time>' line into index.html in every pod's volume on the primary cluster. That line is also what stops nginx answering 403 with 'directory index of ... is forbidden' - a new volume is empty and is mounted over the directory nginx serves, so until a file exists there is nothing to return. This command is the same write by hand, for pod 0, to replace the line with a newer one right before the backup so you know exactly what to look for after the restore. A volume holding no line would make a restore that moved no data indistinguishable from one that did, which is the failure this whole project is built to make visible"
      value       = "kubectl config use-context primary && ${module.primary_stateful_workload.write_test_data_command}"
    }
    backup_command = {
      order       = 9
      title       = "6. Take the backup"
      description = "--snapshot-move-data puts the volume contents in the bucket instead of leaving a source-only EBS snapshot. The command excludes TargetGroupBinding because it is owned by the load balancer controller and contains a target group ARN tied to the source cluster; restoring it fails admission, while restoring the Service correctly makes the secondary controller create a local replacement. Not something the apply does: a backup is an act, not infrastructure"
      value       = "kubectl config use-context primary && velero backup create web --snapshot-move-data --include-namespaces ${var.workload_namespace} --exclude-resources targetgroupbindings.elbv2.k8s.aws --wait"
    }
    backup_describe_command = {
      order       = 10
      title       = "7. Read what the backup actually captured"
      description = "Look at the item count and the data upload section. A backup that says Completed with zero volume snapshots is the EnableCSI feature or the snapshot class label - both of which produce a successful-looking backup with no data in it"
      value       = "velero backup describe web --details"
    }
    list_backups_command = {
      order       = 11
      title       = "8. Confirm the objects reached the bucket"
      description = "Velero writes each backup under backups/<name>/. An empty listing after a backup reported Completed means it went somewhere else, which is a BackupStorageLocation pointing at a different bucket"
      value       = module.velero_backup_bucket.list_backups_command
    }
    restore_command = {
      order       = 12
      title       = "9. Restore into the second cluster"
      description = "Switch context first. The backup has to have synced into this cluster's Velero before it can be named - velero backup get on the secondary side is what confirms that, and it can take a minute after the backup completes because the sync is a poll of the bucket rather than a push"
      value       = "kubectl config use-context secondary && velero backup get && ${module.secondary_velero.restore_command}"
    }
    read_test_data_command = {
      order       = 13
      title       = "10. Prove the data moved, not just the objects"
      description = "The line the primary's volume held when the backup was taken - the one the apply wrote, or the one from step 5 if you refreshed it - should come back here, from a volume this cluster built out of the backup. A StatefulSet that exists with an empty volume means the objects were restored and the data was not - which is the result the checks in steps 2, 3 and 6 exist to prevent"
      value       = "kubectl config use-context secondary && ${module.primary_stateful_workload.read_test_data_command}"
    }
    restored_load_balancer_command = {
      order       = 14
      title       = "11. Read the restored Service's address"
      description = "The restore recreates the Service, and the secondary cluster's own load balancer controller builds a new NLB for it. Compare the owned-load-balancer lists for the two clusters: each load balancer should be tagged for the cluster it is actually in, which is what the _monolithic template's clusterName mix-up broke"
      value       = "kubectl config use-context secondary && ${module.primary_stateful_workload.load_balancer_hostname_command}"
    }
    primary_owned_load_balancers_command = {
      order       = 15
      title       = "Which load balancers each controller owns"
      description = "Run both. A load balancer tagged for the primary cluster while living in the secondary is the _monolithic template's bug - its second helm install passed the first cluster's name - and nothing else makes it visible (rules.md G-3)"
      value       = "${module.primary_aws_load_balancer_controller.owned_load_balancer_command} ; ${module.secondary_aws_load_balancer_controller.owned_load_balancer_command}"
    }
    velero_log_command = {
      order       = 16
      title       = "When something does not work"
      description = "An AccessDenied here is the Pod Identity association; a NoSuchBucket is the BackupStorageLocation; a snapshot that never becomes ready is the snapshot-controller addon. Run it against whichever side is failing"
      value       = module.primary_velero.log_command
    }
    teardown_note = {
      order       = 17
      title       = "Tearing this down"
      description = "force_destroy is on for the backup bucket, so terraform destroy deletes every backup and every version of every backup along with it - there is no recovering them afterwards. The EBS snapshots go too, because the VolumeSnapshotClass uses deletionPolicy Delete (rules.md I-4)"
      value       = "terraform destroy   # deletes ${module.velero_backup_bucket.bucket_name} and its contents"
    }
    update_kubeconfig_command = {
      order       = 18
      title       = "Re-point kubectl"
      description = "User data already set up both contexts, named primary and secondary. Re-run these if the kubeconfig is lost"
      value       = "aws eks update-kubeconfig --region ${data.aws_region.current.region} --name ${module.primary_eks_cluster.cluster_name} --alias primary && aws eks update-kubeconfig --region ${data.aws_region.current.region} --name ${module.secondary_eks_cluster.cluster_name} --alias secondary"
    }
  }
  # Iterating local.outputs directly would order sections by key. Re-keying by the order field and
  # taking values() - which returns a map's values ordered by key - makes the README read top to bottom
  # while the order stays decided by configuration.
  readme_ordered = values({
    for key, entry in local.outputs : format("%02d-%s", entry.order, key) => entry
  })
  readme_body = join("\n", concat(
    ["# velero cross-cluster restore (single-region rehearsal)", ""],
    flatten([for entry in local.readme_ordered : [
      "## ${entry.title}", "", entry.description, "", "```", entry.value, "```", "",
    ]]),
  ))
}
# The work happens inside code-server in a browser, where terraform output is not available, so every
# output above is also written to a README in the home directory the IDE opens (rules.md H-2).
# Combining several modules' outputs is the root's job, so this lives here rather than inside the
# instance module.
resource "aws_ssm_association" "vscode_readme" {
  name                             = "AWS-RunShellScript"
  wait_for_success_timeout_seconds = var.readme_timeout_seconds
  targets {
    key    = "InstanceIds"
    values = [module.vscode_ec2.instance_id]
  }
  parameters = {
    # The until loop, not depends_on or wait_for_success_timeout_seconds, is what orders this after the
    # bootstrap (rules.md D-5). The marker path comes back out of the module it was passed into, so it
    # is defined once (rules.md B-5).
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
