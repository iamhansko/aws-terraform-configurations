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
  # The load balancer controller finds where to put a load balancer by these tags, and the _monolithic
  # template tagged no subnets at all - so the demo Service would have failed with "couldn't
  # auto-discover subnets" even once the controller was installed (rules.md G-1).
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
# The bucket Velero writes to in this account, and the source of the replication below.
#
# The name is required rather than generated, unlike the cluster variant's: the other account's root
# needs to know it for its own reporting, and keeping both names explicit is what makes the pair
# readable (rules.md I-2).
#
# The precondition is the one guard against applying this root with the wrong account's credentials.
# Nothing else catches it: the bucket, the role and the cluster would all be created successfully in
# the other account, and the failure would show up much later as replication that never happens
# (rules.md I-2).
module "velero_backup_bucket" {
  source = "./modules/velero_backup_bucket"

  bucket_name   = var.primary_bucket_name
  force_destroy = var.backup_bucket_force_destroy
  # No replication_source_role_arns: this bucket is the source of a replication, not the destination of
  # one, so it needs no policy admitting another account's role (rules.md B-4).

  depends_on = [module.network]
}
# Guards against applying this root into the wrong account. A variable validation cannot do this - it
# may not reference a data source - so it is a check block, which runs during plan and reports without
# blocking, plus the precondition inside the replication module which does block (rules.md I-2).
check "applied_into_expected_account" {
  assert {
    condition     = data.aws_caller_identity.current.account_id == var.primary_account_id
    error_message = "This root is being applied with credentials for account ${data.aws_caller_identity.current.account_id}, but primary_account_id says ${var.primary_account_id}. The source bucket, the replication role and the cluster would all be created in the wrong account, and the only symptom would be replication that never happens (rules.md I-2)."
  }
}
# The replication that carries the backups to the other account. The source half of a coupling that
# spans two state files: this module is handed the destination bucket's name and the role name to
# create, both as literal strings the two roots agree on, because neither can reference the other
# (rules.md I-1/I-2).
module "s3_cross_account_replication" {
  source = "./modules/s3_cross_account_replication"

  role_name         = var.replication_role_name
  source_account_id = var.primary_account_id
  # The bucket this root created, taken from its output so the replication cannot be attached to a
  # bucket that was never made (rules.md B-5).
  source_bucket_name = module.velero_backup_bucket.bucket_name
  source_bucket_arn  = module.velero_backup_bucket.bucket_arn
  # The bucket in the other account, as a string. secondary_account/ must have been applied already -
  # S3 rejects a replication configuration whose destination does not exist, which is why the apply
  # order in the outputs below is not advice (rules.md I-4).
  destination_account_id   = var.secondary_account_id
  destination_bucket_name  = var.secondary_bucket_name
  replication_time_minutes = var.replication_time_minutes

  depends_on = [
  module.network, module.velero_backup_bucket]
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
  # nodes need it to join Ready (rules.md C-4). It is also what makes the demo Service's target-type ip
  # work, by making pod addresses routable in the VPC (rules.md G-1).
  depends_on = [module.network, module.eks_cluster]
}
module "eks_kube_proxy_addon" {
  source = "./modules/eks_kube_proxy_addon"

  cluster_name = module.eks_cluster.cluster_name

  # Same reasoning as the vpc-cni addon (rules.md C-4).
  depends_on = [module.network, module.eks_cluster]
}
# The credential mechanism every controller here uses. A DaemonSet, so it reaches ACTIVE with zero
# nodes (rules.md C-4) - but it has to exist before the load balancer controller, the EBS CSI driver or
# Velero start, because without the agent on the node their pods get no credentials and log an
# AccessDenied loop rather than failing.
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
module "eks_ebs_csi_driver_addon" {
  source = "./modules/eks_ebs_csi_driver_addon"

  cluster_name     = module.eks_cluster.cluster_name
  role_name_prefix = "${var.prefix}-ebs-csi-"

  # The addon's own pod_identity_association needs the agent already installed, and its controller is a
  # Deployment so it needs schedulable capacity (rules.md C-4/D-2).
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
module "velero" {
  source = "./modules/velero"

  cluster_name     = module.eks_cluster.cluster_name
  role_name_prefix = "${var.prefix}-velero-"
  bucket_name      = module.velero_backup_bucket.bucket_name
  bucket_arn       = module.velero_backup_bucket.bucket_arn
  # The bucket's region and the cluster's region, which here are the same - this account's bucket is
  # local to this account's cluster, and the region boundary is crossed by S3 replication rather than
  # by Velero. The two are separate variables because they are separate things, which the _monolithic
  # template could not tell apart when everything shared one region (rules.md I-3).
  bucket_region    = module.velero_backup_bucket.bucket_region
  snapshot_region  = data.aws_region.current.region
  chart_version    = var.velero_chart_version
  plugin_image_tag = var.velero_plugin_image_tag

  # Velero's CSI support needs the snapshot CRDs and a snapshot class to exist, and its Deployment needs
  # schedulable capacity and DNS. Ordering the module after the storage classes also means terraform
  # destroy removes Velero after them, so it is still running when its own objects go
  # (rules.md D-2/D-4).
  depends_on = [
    module.network,
    module.eks_node_group,
    module.eks_coredns_addon,
    module.eks_pod_identity_agent_addon,
    module.csi_storage_classes,
  ]
}
# The workload the backup is taken of. Only in this account - the other account receives it through a
# restore, which is the demonstration.
module "stateful_workload" {
  source = "./modules/stateful_workload"

  name      = var.workload_name
  namespace = var.workload_namespace
  replicas  = var.workload_replicas
  image     = var.workload_image
  # The class the storage module created, not a restatement of its name. A claim naming a class that
  # does not exist stays Pending and the StatefulSet says nothing about why (rules.md B-5).
  storage_class_name = module.csi_storage_classes.storage_class_name
  volume_size        = var.workload_volume_size

  # The claims need the EBS CSI driver and the StorageClass; the Service needs the load balancer
  # controller to be reconciling, or the in-tree provider claims it and builds a Classic Load Balancer
  # instead (rules.md G-1). Ordering the module after the controller also makes terraform destroy delete
  # the Service while the controller is still alive, so the load balancer is cleaned up rather than
  # orphaned (rules.md D-4).
  depends_on = [
  module.network, module.csi_storage_classes, module.aws_load_balancer_controller]
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
  # carries all five tools (rules.md H-1). None of them creates anything: Velero, the controller, the
  # storage classes and the workload that the _monolithic template installed from here are Terraform
  # resources now (rules.md E-1). The velero CLI stays because taking a backup is the demo, and that is
  # deliberately a manual act rather than something an apply does.
  #
  # Only one kubeconfig context here, unlike the cluster variant's two - the restore happens in the
  # other account, on its own workbench, with its own credentials. That is the shape of a cross-account
  # setup: there is no single place from which both sides can be driven (rules.md I-1).
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
    # The velero CLI, for taking backups by hand. The server side is a Helm release, so this is not
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
  # Two entries here are not values at all but the apply and destroy order across the two accounts.
  # Terraform cannot enforce an order between separate state files, so it is a procedure - and a
  # procedure the operator needs while working inside code-server, where the repository's README is not
  # available (rules.md I-4).
  outputs = {
    apply_order = {
      order       = 1
      title       = "Before applying this root"
      description = "secondary_account must already be applied, with that account's credentials. S3 rejects a replication configuration whose destination bucket does not exist, and the rejection happens partway through this apply rather than in plan. Terraform cannot express this: the two roots are separate state files in separate accounts, so there is nothing for depends_on to point at (rules.md I-1/I-4)"
      value       = "cd ../secondary_account && terraform apply   # first, with the secondary account's credentials"
    }
    vscode_url = {
      order       = 2
      title       = "code-server"
      description = "Open the IDE here. Every command below is meant to be run from its terminal, where kubectl, helm, eksctl and the velero CLI are installed and the cluster context is already configured. The restore side has its own workbench in the other account - there is no single place from which both can be driven"
      value       = module.vscode_ec2.vscode_url
    }
    agreed_names = {
      order       = 3
      title       = "The two names both accounts have to agree on"
      description = "These are the only things crossing the account boundary, and they cross as literal strings because the two roots are separate state files (rules.md I-2). secondary_account's replication_source_role_name must equal the role name, and its secondary_bucket_name must equal the destination bucket. They disagreeing is the most likely way this project fails, and the only symptom is objects whose replication status stays FAILED"
      value       = "replication role: ${module.s3_cross_account_replication.role_name} | destination bucket: ${module.s3_cross_account_replication.destination_bucket_name}"
    }
    replication_role_arn = {
      order       = 4
      title       = "Replication role ARN"
      description = "The exact role ARN the other account's bucket policy must carry in its aws:PrincipalArn condition. The policy Principal itself is this account's root ARN so it can be created before the role exists; comparing this output with the condition value is the cross-state agreement check"
      value       = module.s3_cross_account_replication.role_arn
    }
    velero_status_command = {
      order       = 5
      title       = "1. Confirm Velero is healthy"
      description = "The BackupStorageLocation must say Available: Unavailable means the plugin image is missing, the bucket region is wrong, or the Pod Identity association is not being used - and a backup taken against an Unavailable location fails immediately rather than silently"
      value       = module.velero.backup_location_check_command
    }
    snapshot_class_check_command = {
      order       = 6
      title       = "2. Confirm the snapshot class carries the Velero label"
      description = "Velero picks a VolumeSnapshotClass by the velero.io/csi-volumesnapshot-class label, not by the default annotation. Missing it means Velero skips the volume entirely and reports the backup as Completed - the quietest failure in this project"
      value       = module.csi_storage_classes.snapshot_class_check_command
    }
    write_test_data_command = {
      order       = 7
      title       = "3. Put something in the volume"
      description = "Do this before the backup. Without it the volume is empty, and a restore in the other account producing an empty volume is indistinguishable from a restore that moved no data - which is the failure this whole project exists to make visible"
      value       = module.stateful_workload.write_test_data_command
    }
    backup_command = {
      order       = 8
      title       = "4. Take the backup"
      description = "--snapshot-move-data puts the volume contents in the bucket instead of leaving a source-only EBS snapshot. The command excludes TargetGroupBinding because it is owned by the load balancer controller and contains a target group ARN tied to this account and region; restoring it in the other account fails admission, while restoring the Service correctly makes that cluster's controller create a local replacement"
      value       = "velero backup create web --snapshot-move-data --include-namespaces ${var.workload_namespace} --exclude-resources targetgroupbindings.elbv2.k8s.aws --wait"
    }
    list_backups_command = {
      order       = 9
      title       = "5. Confirm the objects reached this account's bucket"
      description = "Velero writes each backup under backups/<name>/. This is the source side; replication starts from here"
      value       = module.velero_backup_bucket.list_backups_command
    }
    replication_status_command = {
      order       = 10
      title       = "6. Confirm replication succeeded"
      description = "Substitute a key from the listing above. PENDING for a while is normal; FAILED means the destination bucket policy does not admit this role, the agreed role name does not match, or the destination bucket does not exist"
      value       = module.s3_cross_account_replication.replication_status_command
    }
    replication_metrics_command = {
      order       = 11
      title       = "7. Or check the aggregate"
      description = "Failed replications over the last hour, which is the view head-object gives one object at a time. Only published because Replication Time Control is on - with replication_time_minutes set to null these metrics do not exist"
      value       = module.s3_cross_account_replication.replication_metrics_command
    }
    restore_side_note = {
      order       = 12
      title       = "8. Restore in the other account"
      description = "From that account's workbench, with its own credentials. Its Velero syncs the replicated backups out of its own bucket, so the backup has to appear in velero backup get there before it can be restored - which takes the replication delay plus Velero's own sync interval"
      value       = "cd ../secondary_account && terraform output restore_command"
    }
    velero_log_command = {
      order       = 13
      title       = "When something does not work"
      description = "An AccessDenied here is the Pod Identity association; a NoSuchBucket is the BackupStorageLocation; a snapshot that never becomes ready is the snapshot-controller addon"
      value       = module.velero.log_command
    }
    teardown_order = {
      order       = 14
      title       = "Tearing this down"
      description = "This root first, then the other one. The replication configuration has to go before the destination bucket, or the destination is deleted while a live replication rule still points at it. force_destroy is on here, so the destroy also deletes every backup and every version of every backup in this account's bucket - the replicas in the other account survive until that root is destroyed too (rules.md I-4)"
      value       = "terraform destroy   # here first, then: cd ../secondary_account && terraform destroy"
    }
    update_kubeconfig_command = {
      order       = 15
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
    ["# velero cross-account DR - primary (source) account", ""],
    flatten([for entry in local.readme_ordered : [
      "## ${entry.title}", "", entry.description, "", "```", entry.value, "```", "",
    ]]),
  ))
}
# The work happens inside code-server in a browser, where terraform output is not available, so every
# output above is also written to a README in the home directory the IDE opens (rules.md H-2). That
# includes the apply and destroy order across the two accounts, which is the part an operator needs
# most and the part a repository README cannot deliver to them (rules.md I-4).
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
