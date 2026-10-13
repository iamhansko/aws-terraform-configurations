# Resolve the public IPv4 address of the machine running Terraform once at the root. The child security
# group modules are ordered after other modules, so putting this plan-time read inside them could defer it
# until apply; passing only the resulting CIDR also keeps the modules independent of the lookup service
# (rules.md B-6/D-6).
data "http" "my_ip" {
  url = var.my_ip_lookup_url

  lifecycle {
    postcondition {
      condition = (
        self.status_code == 200 &&
        can(regex("^[0-9]{1,3}(\\.[0-9]{1,3}){3}$", trimspace(self.response_body))) &&
        can(cidrhost("${trimspace(self.response_body)}/32", 0))
      )
      error_message = "my_ip_lookup_url must return HTTP 200 with one bare IPv4 address. Set it to a trusted HTTPS address-reflection endpoint reachable from the machine running Terraform."
    }
  }
}
locals {
  my_ip_cidr = "${trimspace(data.http.my_ip.response_body)}/32"
}

data "aws_region" "current" {}
data "aws_caller_identity" "current" {}
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
  # The restored Service is type LoadBalancer, so the load balancer controller in this account needs
  # these tags to find where to put its load balancer - and the restore is what creates that Service,
  # so the tags have to be here before it happens (rules.md G-1).
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
locals {
  # The other account's replication role, assembled from an account ID and an agreed name rather than
  # referenced. It is in a different account and a different state file, so there is nothing to
  # reference, and it does not exist yet when this root is applied. The bucket policy therefore names
  # the source account root (which always exists) as Principal and uses aws:PrincipalArn to admit only
  # this exact future role. Naming the absent role directly is rejected by S3 as an invalid principal;
  # the condition-based form is what lets this root apply first without broadening access
  # (rules.md I-2/I-4).
  replication_source_role_arn = "arn:aws:iam::${var.primary_account_id}:role/${var.replication_source_role_name}"
}
# The destination bucket. This root is applied first, because the other account's replication
# configuration names this bucket and S3 refuses a configuration whose destination does not exist
# (rules.md I-4).
module "velero_backup_bucket" {
  source = "./modules/velero_backup_bucket"

  bucket_name   = var.secondary_bucket_name
  force_destroy = var.backup_bucket_force_destroy
  # The bucket policy half of the cross-account grant. Replication needs a grant on both sides: the
  # source account's role has to be allowed to write, which is in that account's policy, and this
  # bucket has to admit the role, which is here. Neither alone is enough, and a missing grant on either
  # side shows up only as an object whose replication status stays FAILED (rules.md I-2).
  replication_source_role_arns = [local.replication_source_role_arn]

  depends_on = [module.network]
}
# Guards against applying this root into the wrong account. A variable validation cannot do this - it
# may not reference a data source - so it is a check block, which reports during plan without blocking
# the apply (rules.md I-2).
check "applied_into_expected_account" {
  assert {
    condition     = data.aws_caller_identity.current.account_id == var.secondary_account_id
    error_message = "This root is being applied with credentials for account ${data.aws_caller_identity.current.account_id}, but secondary_account_id says ${var.secondary_account_id}. The destination bucket would be created in the wrong account, and the other root's replication would then fail with AccessDenied against a bucket that exists but is not the one it was told about (rules.md I-2)."
  }
}
module "eks_cluster" {
  source = "./modules/eks_cluster"

  name                   = var.cluster_name
  kubernetes_version     = var.kubernetes_version
  subnet_ids             = concat(module.network.public_subnet_ids, module.network.private_subnet_ids)
  endpoint_public_access = var.endpoint_public_access
  public_access_cidrs    = var.public_access_cidrs

  # Referencing module.network.*_subnet_ids only orders this after the specific aws_subnet resources
  # behind those outputs, not after the NAT gateways and route table associations that never surface as
  # outputs (rules.md D-3).
  depends_on = [module.network]
}
module "eks_vpc_cni_addon" {
  source = "./modules/eks_vpc_cni_addon"

  cluster_name = module.eks_cluster.cluster_name

  # bootstrap_self_managed_addons = false on the cluster means vpc-cni does not exist until this addon
  # creates it. As a DaemonSet it reaches ACTIVE with zero nodes, so it comes before any capacity - and
  # nodes need it to join Ready (rules.md C-4). It is also what makes the restored Service's
  # target-type ip work, by making pod addresses routable in the VPC (rules.md G-1).
  depends_on = [module.network, module.eks_cluster]
}
module "eks_kube_proxy_addon" {
  source = "./modules/eks_kube_proxy_addon"

  cluster_name = module.eks_cluster.cluster_name

  # Same reasoning as the vpc-cni addon (rules.md C-4).
  depends_on = [module.network, module.eks_cluster]
}
module "eks_pod_identity_agent_addon" {
  source = "./modules/eks_pod_identity_agent_addon"

  cluster_name = module.eks_cluster.cluster_name

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
# The driver on the restoring side, and the reason a restore produces a working volume rather than a
# Pending claim: the data in the backup has to be turned back into an EBS volume here. It is also the
# half that cannot be restored - a backup contains no CSI driver, so this has to exist beforehand.
module "eks_ebs_csi_driver_addon" {
  source = "./modules/eks_ebs_csi_driver_addon"

  cluster_name     = module.eks_cluster.cluster_name
  role_name_prefix = "${var.prefix}-ebs-csi-"

  depends_on = [
  module.network, module.eks_pod_identity_agent_addon, module.eks_node_group]
}
module "eks_snapshot_controller_addon" {
  source = "./modules/eks_snapshot_controller_addon"

  cluster_name = module.eks_cluster.cluster_name

  depends_on = [
  module.network, module.eks_node_group]
}
module "aws_load_balancer_controller" {
  source = "./modules/aws_load_balancer_controller"

  cluster_name                   = module.eks_cluster.cluster_name
  vpc_id                         = module.network.vpc_id
  aws_region                     = data.aws_region.current.region
  role_name_prefix               = "${var.prefix}-lbc-"
  chart_version                  = var.aws_load_balancer_controller_chart_version
  enable_service_mutator_webhook = var.enable_service_mutator_webhook

  # The controller pod needs schedulable capacity, working cluster DNS and the pod identity agent
  # before it can reach the AWS API, and wait = true on its Helm release would otherwise time out
  # (rules.md D-2).
  depends_on = [
    module.network,
    module.eks_node_group,
    module.eks_coredns_addon,
    module.eks_pod_identity_agent_addon,
  ]
}
# The storage classes have to exist before the restore, not after. A restored PersistentVolumeClaim
# names its StorageClass, and a claim naming a class this cluster does not have stays Pending - Velero
# does not create StorageClasses unless they were in the backup, and the backup covers one namespace
# while a StorageClass is cluster-scoped.
module "csi_storage_classes" {
  source = "./modules/csi_storage_classes"

  # The VolumeSnapshotClass instantiates a CRD the snapshot-controller addon installs, and the
  # StorageClass is useless without the EBS CSI driver. Neither is expressed by a value reference
  # (rules.md D-2/E-2).
  depends_on = [
    module.network,
    module.eks_snapshot_controller_addon,
    module.eks_ebs_csi_driver_addon,
    module.eks_coredns_addon,
  ]
}
# Velero on the restoring side, pointed at this account's bucket - the one the other account replicates
# into. That is the whole mechanism: this Velero never talks to the other account, it only reads objects
# that arrived in a bucket it owns.
module "velero" {
  source = "./modules/velero"

  cluster_name     = module.eks_cluster.cluster_name
  role_name_prefix = "${var.prefix}-velero-"
  bucket_name      = module.velero_backup_bucket.bucket_name
  bucket_arn       = module.velero_backup_bucket.bucket_arn
  # This account's bucket and this account's region. The region boundary was crossed by S3 replication
  # before Velero ever saw these objects, which is why both values are local here - and why they were
  # indistinguishable in the _monolithic template, where nothing crossed a boundary at all
  # (rules.md I-3).
  bucket_region    = module.velero_backup_bucket.bucket_region
  snapshot_region  = data.aws_region.current.region
  chart_version    = var.velero_chart_version
  plugin_image_tag = var.velero_plugin_image_tag

  depends_on = [
    module.network,
    module.eks_node_group,
    module.eks_coredns_addon,
    module.eks_pod_identity_agent_addon,
    module.csi_storage_classes,
  ]
}
module "vscode_ec2" {
  source = "./modules/vscode_ec2"

  vpc_id                      = module.network.vpc_id
  subnet_id                   = module.network.public_subnet_a_id
  key_name                    = module.key_pair.key_name
  instance_type               = var.vscode_instance_type
  allow_inbound_from_anywhere = var.allow_inbound_from_anywhere
  my_ip_cidr                  = local.my_ip_cidr
  marker_file_path            = var.marker_file_path
  # Joining the cluster security group is what lets this instance reach the API server. The module is
  # handed an ID list and never learns it belongs to an EKS cluster (rules.md B-6).
  extra_security_group_ids = [module.eks_cluster.cluster_security_group_id]

  # An EKS cluster and this instance share a root module, so it is the workbench for that cluster and
  # carries all five tools (rules.md H-1). None of them creates anything: Velero, the controller and the
  # storage classes that the _monolithic template installed from here are Terraform resources now
  # (rules.md E-1). The velero CLI stays because running the restore is the demo, and that is
  # deliberately a manual act rather than something an apply does.
  #
  # One kubeconfig context, for this account's cluster only. The backup side is in the other account
  # with its own workbench and its own credentials - there is no single place from which both halves can
  # be driven, which is what a real cross-account setup looks like (rules.md I-1).
  #
  # Three bugs from the _monolithic template are fixed rather than carried over. It ran "exec bash"
  # partway through the user data, which replaces the shell and discards every line after it - eksctl,
  # helm, every manifest, the helm install and the whole Velero setup were below that line, so the
  # project never did anything at all. It pulled eksctl from weaveworks; eksctl-io is the project's own
  # org (rules.md H-1). And it wrote "complete -o default -F __start_kubectl k" into .bashrc before the
  # line that sources kubectl's completion, so every login printed a "function not found" error.
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
    # The velero CLI, for running the restore by hand. The server side is a Helm release, so this is not
    # what installs Velero - it only talks to it.
    curl -sL -o velero.tar.gz https://github.com/vmware-tanzu/velero/releases/download/${var.velero_cli_version}/velero-${var.velero_cli_version}-linux-amd64.tar.gz
    tar -xzf velero.tar.gz
    sudo install -m 0755 velero-${var.velero_cli_version}-linux-amd64/velero /usr/local/bin/velero
    rm -r velero.tar.gz velero-${var.velero_cli_version}-linux-amd64
    echo 'source <(velero completion bash)' >> ~/.bashrc
    aws configure set default.region ${data.aws_region.current.region}
    aws eks update-kubeconfig --region ${data.aws_region.current.region} --name ${module.eks_cluster.cluster_name}
    EOF
  EOT

  depends_on = [module.network]
}
# Granting the workbench's instance role cluster access joins two modules that know nothing about each
# other, so it belongs in the root (rules.md C-1).
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
  #
  # Two entries are not values but the apply and destroy order across the two accounts. Terraform cannot
  # enforce an order between separate state files, so it is a procedure - and one the operator needs
  # while working inside code-server, where the repository's README is not available (rules.md I-4).
  outputs = {
    apply_order = {
      order       = 1
      title       = "This root is applied first"
      description = "Before primary_account, and with this account's credentials. Its replication configuration names this bucket, and S3 refuses a configuration whose destination does not exist. This side can go first because its bucket policy names the source account root, which already exists, then uses aws:PrincipalArn to admit only the agreed replication role even though that role is created later (rules.md I-2/I-4)"
      value       = "terraform apply   # here first, then: cd ../primary_account && terraform apply"
    }
    vscode_url = {
      order       = 2
      title       = "code-server"
      description = "Open the IDE here. Every command below is meant to be run from its terminal, where kubectl, helm, eksctl and the velero CLI are installed and the cluster context is already configured. The backup side is in the other account with its own workbench"
      value       = module.vscode_ec2.vscode_url
    }
    agreed_names = {
      order       = 3
      title       = "The two names both accounts have to agree on"
      description = "These are the only things crossing the account boundary, and they cross as literal strings because the two roots are separate state files (rules.md I-2). primary_account's secondary_bucket_name must equal this bucket, and its replication_role_name must equal the role this bucket's policy admits. They disagreeing is the most likely way this project fails, and the only symptom is objects whose replication status stays FAILED on the other side"
      value       = "this bucket: ${module.velero_backup_bucket.bucket_name} | admitted role: ${local.replication_source_role_arn}"
    }
    bucket_policy_check_command = {
      order       = 4
      title       = "1. Confirm the bucket policy admits the right role"
      description = "Compare the aws:PrincipalArn condition with the other account's replication_role_arn output. Principal should be that account's root ARN; the condition narrows it to the agreed role assembled here from the account ID and role name, because no cross-state reference can keep them in step"
      value       = "aws s3api get-bucket-policy --bucket ${module.velero_backup_bucket.bucket_name} --query Policy --output text | python -m json.tool"
    }
    velero_status_command = {
      order       = 5
      title       = "2. Confirm Velero is healthy"
      description = "The BackupStorageLocation must say Available: Unavailable means the plugin image is missing, the bucket region is wrong, or the Pod Identity association is not being used. Velero here reads this account's bucket - it never talks to the other account at all"
      value       = module.velero.backup_location_check_command
    }
    storage_class_check_command = {
      order       = 6
      title       = "3. Confirm the storage class exists before restoring"
      description = "A restored PersistentVolumeClaim names its StorageClass, and a claim naming a class this cluster does not have stays Pending. Velero does not restore StorageClasses unless they were in the backup, and the backup covers one namespace while a StorageClass is cluster-scoped - so this has to be here first"
      value       = module.csi_storage_classes.storage_class_check_command
    }
    list_replicated_backups_command = {
      order       = 7
      title       = "4. Confirm the backup replicated into this bucket"
      description = "Velero writes each backup under backups/<name>/, and replication reproduces that layout. An empty listing after the other account reported a completed backup means replication has not finished or has failed - that account's replication_status_command is where the reason is"
      value       = module.velero_backup_bucket.list_backups_command
    }
    sync_check_command = {
      order       = 8
      title       = "5. Wait for Velero to notice it"
      description = "Velero finds backups by polling its BackupStorageLocation rather than being told, so a replicated backup appears here on the next sync rather than immediately. A restore cannot name a backup this list does not show"
      value       = "velero backup get"
    }
    restore_command = {
      order       = 9
      title       = "6. Restore"
      description = "This is the demonstration: the StatefulSet, its claims and the data in its volumes are all rebuilt here from objects that arrived in this account's bucket. Nothing in this configuration created the workload"
      value       = module.velero.restore_command
    }
    restore_describe_command = {
      order       = 10
      title       = "7. Read what the restore did"
      description = "Warnings about resources that already exist are normal - Velero skips them. A restore that says Completed while the pods stay Pending is a storage class or a CSI driver problem, and both are things the restore cannot bring with it"
      value       = "velero restore describe <restore-name> --details"
    }
    restored_volume_check_command = {
      order       = 11
      title       = "8. Confirm the volumes came back"
      description = "One claim per restored pod, each Bound. A claim stuck Pending means the data movement did not complete or the storage class is missing - and the StatefulSet itself reports nothing about either"
      value       = "kubectl -n ${var.workload_namespace} get pvc,pv,pods -o wide"
    }
    read_test_data_command = {
      order       = 12
      title       = "9. Prove the data crossed the boundary"
      description = "The line written on the other account's cluster before the backup should come back here, out of a volume this cluster built from objects that travelled through two buckets in two regions. A StatefulSet that exists with an empty volume means the objects were restored and the data was not - which is what --snapshot-move-data on the backup side prevents"
      value       = "kubectl -n ${var.workload_namespace} exec ${var.workload_name}-0 -- cat ${var.workload_mount_path}/index.html"
    }
    restored_load_balancer_command = {
      order       = 13
      title       = "10. Read the restored Service's address"
      description = "The restore recreates the Service, and this account's own load balancer controller builds a new load balancer for it. The address is different from the original by necessity - a load balancer is not something a backup can carry"
      value       = "kubectl -n ${var.workload_namespace} get service -o wide"
    }
    velero_log_command = {
      order       = 14
      title       = "When something does not work"
      description = "An AccessDenied here is the Pod Identity association; a NoSuchBucket is the BackupStorageLocation; a snapshot that never becomes ready is the snapshot-controller addon. A backup that never appears is replication rather than Velero, and that is diagnosed from the other account"
      value       = module.velero.log_command
    }
    teardown_order = {
      order       = 15
      title       = "Tearing this down"
      description = "This root second, after primary_account. Its replication configuration has to go first, or it is left pointing at a bucket that no longer exists. force_destroy is on here, so the destroy deletes every replicated backup and every version of it - and those are the copies that were supposed to survive the primary region (rules.md I-4)"
      value       = "cd ../primary_account && terraform destroy   # first, then back here: terraform destroy"
    }
    update_kubeconfig_command = {
      order       = 16
      title       = "Re-point kubectl"
      description = "User data already ran this. Re-run it if the kubeconfig is ever lost"
      value       = "aws eks update-kubeconfig --region ${data.aws_region.current.region} --name ${module.eks_cluster.cluster_name}"
    }
  }
  # Iterating local.outputs directly would order sections by key. Re-keying by the order field and
  # taking values() - which returns a map's values ordered by key - makes the README read top to bottom
  # while the order stays decided by configuration.
  readme_ordered = values({
    for key, entry in local.outputs : format("%02d-%s", entry.order, key) => entry
  })
  readme_body = join("\n", concat(
    ["# velero cross-account DR - secondary (destination) account", ""],
    flatten([for entry in local.readme_ordered : [
      "## ${entry.title}", "", entry.description, "", "```", entry.value, "```", "",
    ]]),
  ))
}
# The work happens inside code-server in a browser, where terraform output is not available, so every
# output above is also written to a README in the home directory the IDE opens (rules.md H-2). That
# includes the apply and destroy order across the two accounts, which is the part an operator needs most
# and the part a repository README cannot deliver to them (rules.md I-4).
resource "aws_ssm_association" "vscode_readme" {
  name                             = "AWS-RunShellScript"
  wait_for_success_timeout_seconds = var.readme_timeout_seconds
  targets {
    key    = "InstanceIds"
    values = [module.vscode_ec2.instance_id]
  }
  parameters = {
    # The until loop, not depends_on or wait_for_success_timeout_seconds, is what orders this after the
    # bootstrap (rules.md D-5). The marker path comes back out of the module it was passed into, so it is
    # defined once (rules.md B-5).
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
