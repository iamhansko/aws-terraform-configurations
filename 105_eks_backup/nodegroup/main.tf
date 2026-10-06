data "aws_region" "current" {}

data "aws_caller_identity" "current" {}

locals {
  # Full zone names, which is what an EBS StorageClass's allowedTopologies takes - the suffixes the
  # network module works in are not the same thing. Derived rather than restated so the class cannot
  # allow a zone the node group does not span (rules.md B-5).
  availability_zones = [for suffix in var.availability_zone_suffixes : "${data.aws_region.current.region}${suffix}"]
}

module "network" {
  source = "./modules/network"

  region                         = data.aws_region.current.region
  vpc_cidr_block                 = var.vpc_cidr_block
  availability_zone_suffixes     = var.availability_zone_suffixes
  nat_availability_zone_suffixes = var.nat_availability_zone_suffixes
  vpc_name                       = "${var.project_name}-vpc"
  # Both roles on every subnet, because a restore into a new cluster reuses these subnets and the
  # controller in that cluster has to be able to discover them (rules.md G-1).
  subnet_tags = {
    "kubernetes.io/role/elb"          = "1"
    "kubernetes.io/role/internal-elb" = "1"
  }
}

module "key_pair" {
  source = "./modules/key_pair"

  key_name = "${var.project_name}-key"

  # Nothing here reads a network output, but the root orders every module after the network so the whole
  # VPC - NAT gateway and route tables included - is finished before anything starts in it
  # (rules.md D-3).
  depends_on = [module.network]
}

# The cluster the backup is taken of. Everything Terraform creates inside a cluster goes here.
module "primary_cluster" {
  source = "./modules/eks_cluster"

  name                      = var.primary_cluster_name
  kubernetes_version        = var.kubernetes_version
  authentication_mode       = var.authentication_mode
  subnet_ids                = concat(module.network.public_subnet_ids, module.network.private_subnet_ids)
  endpoint_public_access    = var.endpoint_public_access
  public_access_cidrs       = var.public_access_cidrs
  enabled_cluster_log_types = var.cluster_log_types

  depends_on = [module.network]
}

# The restore target, and deliberately nothing more: no addons, no capacity, no Kubernetes objects.
# AWS Backup writes into it, and anything Terraform created here would be a second owner of something a
# restore is about to replace.
#
# The same module as the primary cluster, instantiated twice. Two module blocks rather than one with
# for_each, because the two are not interchangeable - the providers above are aimed at the primary, and
# only the primary gets addons and capacity.
module "secondary_cluster" {
  source = "./modules/eks_cluster"
  count  = var.create_secondary_cluster ? 1 : 0

  name                      = var.secondary_cluster_name
  kubernetes_version        = var.kubernetes_version
  authentication_mode       = var.authentication_mode
  subnet_ids                = concat(module.network.public_subnet_ids, module.network.private_subnet_ids)
  endpoint_public_access    = var.endpoint_public_access
  public_access_cidrs       = var.public_access_cidrs
  enabled_cluster_log_types = var.cluster_log_types

  depends_on = [module.network]
}

# vpc-cni and kube-proxy are DaemonSets, so they reach ACTIVE with zero nodes. They come before the node
# group because a node cannot join Ready without them, and with
# bootstrap_self_managed_addons = false nothing installs them otherwise (rules.md C-4).
module "eks_vpc_cni_addon" {
  source = "./modules/eks_vpc_cni_addon"

  cluster_name = module.primary_cluster.cluster_name

  depends_on = [module.network, module.primary_cluster]
}

module "eks_kube_proxy_addon" {
  source = "./modules/eks_kube_proxy_addon"

  cluster_name = module.primary_cluster.cluster_name

  depends_on = [module.network, module.primary_cluster]
}

# The Pod Identity agent. Worth noting for this project specifically: a restore into a new cluster
# recreates Pod Identity associations, so the ones on this cluster are part of what the backup captures.
module "eks_pod_identity_agent_addon" {
  source = "./modules/eks_pod_identity_agent_addon"

  cluster_name = module.primary_cluster.cluster_name

  depends_on = [module.network, module.primary_cluster]
}

module "eks_node_group" {
  source = "./modules/eks_node_group"

  cluster_name    = module.primary_cluster.cluster_name
  node_group_name = var.node_group_name
  instance_types  = var.node_instance_types
  desired_size    = var.node_desired_size
  min_size        = var.node_min_size
  max_size        = var.node_max_size
  labels          = var.node_labels
  key_name        = module.key_pair.key_name
  subnet_ids      = module.network.private_subnet_ids

  depends_on = [module.network, module.eks_vpc_cni_addon, module.eks_kube_proxy_addon]
}

# coredns is a Deployment, so unlike the DaemonSets it needs schedulable node capacity to leave DEGRADED
# and become ACTIVE (rules.md C-4).
module "eks_coredns_addon" {
  source = "./modules/eks_coredns_addon"

  cluster_name          = module.primary_cluster.cluster_name
  coredns_replica_count = var.coredns_replica_count

  depends_on = [
  module.network, module.eks_node_group]
}

# The three CSI drivers, one module each (rules.md C-4). They are what makes the backup interesting:
# AWS Backup captures a persistent volume only when its claim is provisioned by one of these drivers -
# an in-tree or CSI-migrated volume is silently absent from the recovery point.
module "eks_ebs_csi_driver_addon" {
  source = "./modules/eks_ebs_csi_driver_addon"

  cluster_name = module.primary_cluster.cluster_name

  depends_on = [
  module.network, module.eks_node_group, module.eks_pod_identity_agent_addon]
}

module "eks_efs_csi_driver_addon" {
  source = "./modules/eks_efs_csi_driver_addon"

  cluster_name      = module.primary_cluster.cluster_name
  oidc_provider_arn = module.primary_cluster.oidc_provider_arn
  oidc_issuer_host  = module.primary_cluster.oidc_issuer_host

  depends_on = [
  module.network, module.eks_node_group]
}

module "eks_mountpoint_s3_csi_driver_addon" {
  source = "./modules/eks_mountpoint_s3_csi_driver_addon"

  cluster_name      = module.primary_cluster.cluster_name
  oidc_provider_arn = module.primary_cluster.oidc_provider_arn
  oidc_issuer_host  = module.primary_cluster.oidc_issuer_host
  # Scoped to this one bucket rather than "*" (rules.md B-6).
  bucket_arns = [module.s3_bucket.bucket_arn]

  depends_on = [
  module.network, module.eks_node_group, module.s3_bucket]
}

# The controller the _monolithic template created an IAM role and a Pod Identity association for and then
# never installed. Nothing here creates an Ingress - AWS Backup cannot restore Services or Ingresses,
# which the project's own notes record - so its purpose is to make that role real and to give the restore
# metadata a Pod Identity association to carry.
module "aws_load_balancer_controller" {
  source = "./modules/aws_load_balancer_controller"
  count  = var.install_load_balancer_controller ? 1 : 0

  cluster_name      = module.primary_cluster.cluster_name
  vpc_id            = module.network.vpc_id
  aws_region        = data.aws_region.current.region
  oidc_provider_arn = module.primary_cluster.oidc_provider_arn
  oidc_issuer_host  = module.primary_cluster.oidc_issuer_host
  chart_version     = var.load_balancer_controller_chart_version
  # Nothing in this project annotates manage-backend-security-group-rules, so the controller's own
  # default is fine and there is no pairing to enforce (rules.md G-2).
  enable_service_mutator_webhook = false

  depends_on = [
    module.network,
    module.eks_node_group,
    module.eks_coredns_addon,
    module.eks_pod_identity_agent_addon,
  ]
}

# --- The storage the backup captures ---

module "efs_file_system" {
  source = "./modules/efs_file_system"

  name   = "${var.project_name}-efs"
  vpc_id = module.network.vpc_id
  # Keyed by zone suffix rather than passed as a list: the subnet ids are another module's output and
  # unknown at plan time, and for_each needs its keys known then (rules.md B-8).
  mount_target_subnet_ids = module.network.private_subnet_ids_by_zone
  performance_mode        = var.efs_performance_mode
  # The primary cluster's security group, which is what its pods carry. The _monolithic template opened
  # NFS to the whole VPC CIDR instead - broader, and it stops describing intent the moment the VPC gains
  # anything else (rules.md B-8).
  ingress_source_security_groups = merge(
    { primary_cluster = module.primary_cluster.cluster_security_group_id },
    # The restore target's pods mount the same file system, so its security group needs the same rule -
    # otherwise a restore succeeds and every restored pod hangs on its mount. This is the kind of thing
    # the _monolithic template's VPC-wide rule hid.
    var.create_secondary_cluster ? { secondary_cluster = module.secondary_cluster[0].cluster_security_group_id } : {},
  )

  depends_on = [module.network]
}

module "s3_bucket" {
  source = "./modules/s3_bucket"

  bucket_prefix = var.s3_bucket_prefix
  force_destroy = var.s3_bucket_force_destroy
  # Versioning on, which AWS Backup requires for a bucket it protects - without it the bucket's child
  # recovery point is absent and the composite parent still reports COMPLETED.
  versioning_enabled = true

  depends_on = [module.network]
}

# Everything the backup is taken of. Not one of these objects existed in the _monolithic template: they
# were all applied by a `kubectl apply` in the workbench's user data, after a line reading `exec bash`
# that discarded the rest of the script. The backup ran against an empty cluster.
module "backup_target_workloads" {
  source = "./modules/backup_target_workloads"

  namespace  = var.workload_namespace
  aws_region = data.aws_region.current.region

  efs_file_system_id = module.efs_file_system.file_system_id
  ebs_volume_type    = var.ebs_volume_type
  ebs_allowed_zones  = local.availability_zones
  s3_bucket_name     = module.s3_bucket.bucket_name
  # Matches the node group's labels, so a restore into a cluster whose nodes do not carry them leaves
  # these pods Pending - which is a useful thing for the demo to show (rules.md B-5).
  app_node_selector = var.node_labels

  # Every driver has to be installed before a claim naming it can bind, the mount targets before a pod
  # can reach the file system, and the node group before anything is scheduled. Ordering the module
  # after them is also what makes `terraform destroy` delete these objects while their drivers are
  # still installed - otherwise a claim's finalizer waits for a controller that is already gone
  # (rules.md D-4).
  depends_on = [
    module.network,
    module.eks_ebs_csi_driver_addon,
    module.eks_efs_csi_driver_addon,
    module.eks_mountpoint_s3_csi_driver_addon,
    module.efs_file_system,
    module.s3_bucket,
    module.eks_node_group,
    module.eks_coredns_addon,
  ]
}

# --- Backup ---

module "eks_backup_vault" {
  source = "./modules/eks_backup_vault"

  name               = "${var.project_name}-vault"
  create_backup_plan = var.create_backup_plan
  backup_schedule    = var.backup_schedule
  delete_after_days  = var.backup_delete_after_days
  # The primary cluster, which is the whole selection. A composite recovery point picks up the attached
  # volumes from the cluster's claims, so the EBS volume, the file system and the bucket do not have to
  # be listed separately.
  protected_resource_arns = [module.primary_cluster.cluster_arn]

  # The workloads have to exist before a scheduled run can capture them. A plan created first would
  # still be correct, but the first recovery point taken would be of an empty cluster - which is exactly
  # what the original produced (rules.md D-2).
  depends_on = [
  module.network, module.backup_target_workloads]
}

# What lets a restore write into the secondary cluster. This is the pair of resources the _monolithic
# template left as two commands in its README for a person to run by hand.
#
# Only the restore target needs them: AWS Backup creates its own access entry on the cluster it backs
# up, but the target of a restore is a different cluster and nothing creates one there. Joining two
# modules that know nothing about each other belongs in the root (rules.md C-1).
resource "aws_eks_access_entry" "backup_restore_access_entry" {
  count = var.create_secondary_cluster ? 1 : 0

  cluster_name  = module.secondary_cluster[0].cluster_name
  principal_arn = module.eks_backup_vault.backup_role_arn
  type          = "STANDARD"
}

resource "aws_eks_access_policy_association" "backup_restore_access_policy_association" {
  count = var.create_secondary_cluster ? 1 : 0

  cluster_name  = module.secondary_cluster[0].cluster_name
  principal_arn = module.eks_backup_vault.backup_role_arn
  policy_arn    = var.restore_access_policy_arn
  access_scope {
    type = "cluster"
  }

  # EKS rejects a policy association for a principal with no access entry yet, and the two resources
  # share only literal argument values, so nothing orders them (rules.md D-1).
  depends_on = [aws_eks_access_entry.backup_restore_access_entry]
}

# --- Workbench ---

module "vscode_ec2" {
  source = "./modules/vscode_ec2"

  name                        = "${var.project_name}-vscode"
  vpc_id                      = module.network.vpc_id
  subnet_id                   = module.network.public_subnet_ids_by_zone[var.availability_zone_suffixes[0]]
  key_name                    = module.key_pair.key_name
  instance_type               = var.vscode_instance_type
  code_server_version         = var.code_server_version
  security_group_name         = "${var.project_name}-vscode-sg"
  allow_inbound_from_anywhere = var.allow_inbound_from_anywhere
  marker_file_path            = var.marker_file_path
  # Both clusters' security groups, so kubectl on this instance can reach either API server without
  # leaving the VPC. The module is handed an ID list and never learns what they belong to
  # (rules.md B-6).
  extra_security_group_ids = concat(
    [module.primary_cluster.cluster_security_group_id],
    var.create_secondary_cluster ? [module.secondary_cluster[0].cluster_security_group_id] : [],
  )
  # An EKS cluster and this instance share a root module, so this instance is the workbench for that
  # cluster and carries all five tools (rules.md H-1).
  #
  # The _monolithic template's script had the same three faults as the rest of this family, and the
  # first one hid the other two. `exec bash` partway through replaced the shell and discarded every
  # remaining line - the eksctl and helm installs, `aws eks update-kubeconfig`, the `helm install` of
  # the load balancer controller, and every `kubectl apply` that was supposed to create the objects the
  # backup would capture. It also wrote the kubectl completion alias before sourcing the completion that
  # defines __start_kubectl, and it ended with `cfn-signal`, a CloudFormation helper with no stack to
  # signal (rules.md H-1).
  #
  # Nothing here creates cluster resources any more: the controller is a Helm release and the backup
  # target objects are provider resources (rules.md E-1).
  additional_user_data = <<-EOT
    dnf install -yq docker git jq
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
    # Order matters: bash_completion has to be sourced before kubectl's own completion, which is what
    # defines __start_kubectl, and that function has to exist before complete references it
    # (rules.md H-1).
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
    rm -f get_helm.sh
    aws configure set default.region ${data.aws_region.current.region}
    # Contexts for both clusters, named so `kubectl config use-context` reads clearly - the demo moves
    # between them. Without this - and without the access entry below - kubectl is installed but every
    # command answers "You must be logged in to the server" (rules.md H-1).
    aws eks update-kubeconfig --region ${data.aws_region.current.region} --name ${module.primary_cluster.cluster_name} --alias primary
    %{if var.create_secondary_cluster~}
    aws eks update-kubeconfig --region ${data.aws_region.current.region} --name ${module.secondary_cluster[0].cluster_name} --alias secondary
    %{endif~}
    kubectl config use-context primary
    EOF
  EOT

  depends_on = [module.network]
}

# The workbench needs access to both clusters: the primary to look at what is being backed up, the
# secondary to see what a restore produced. for_each over a static map, because the keys have to be
# known during plan even though the cluster names are not (rules.md B-8).
resource "aws_eks_access_entry" "vscode_access_entry" {
  for_each = local.workbench_clusters

  cluster_name  = each.value
  principal_arn = module.vscode_ec2.iam_role_arn
  type          = "STANDARD"
}

resource "aws_eks_access_policy_association" "vscode_access_policy_association" {
  for_each = local.workbench_clusters

  cluster_name  = each.value
  principal_arn = module.vscode_ec2.iam_role_arn
  policy_arn    = "arn:aws:eks::aws:cluster-access-policy/AmazonEKSClusterAdminPolicy"
  access_scope {
    type = "cluster"
  }

  depends_on = [aws_eks_access_entry.vscode_access_entry]
}

locals {
  # The command that starts a backup of the primary cluster, composed once. The association below runs
  # it and the output projects it, so the operator's copy and the apply's copy cannot drift
  # (rules.md B-5). The vault module supplies everything but the resource ARN, because it knows nothing
  # about the cluster (rules.md B-6).
  start_backup_command = "${module.eks_backup_vault.start_backup_command} ${module.primary_cluster.cluster_arn}"
  # Literal keys, cluster names as values. The names come from module outputs and are unknown during
  # plan, so they cannot be keys (rules.md B-8).
  workbench_clusters = merge(
    { primary = module.primary_cluster.cluster_name },
    var.create_secondary_cluster ? { secondary = module.secondary_cluster[0].cluster_name } : {},
  )
  # A restore metadata skeleton with everything Terraform already knows filled in. The
  # _monolithic template's README left two "⚠️" placeholders here and expected the reader to build the
  # document by hand from the console.
  #
  # What is still missing is only what a completed backup can supply: the recovery point ARNs, and the
  # nestedRestoreJobs entry each child recovery point needs. The project's manifests/ directory holds a
  # captured example of the finished article.
  restore_metadata = {
    existing_cluster = jsonencode({
      clusterName            = var.create_secondary_cluster ? module.secondary_cluster[0].cluster_name : var.secondary_cluster_name
      newCluster             = false
      kubernetesRestoreOrder = []
      namespaces             = []
      namespacePvMapping = {
        # Every volume the backup captured, grouped by the namespace whose claims referenced them. The
        # EBS volume id is not here because it only exists once a pod has bound the claim.
        (var.workload_namespace) = [
          "arn:aws:elasticfilesystem:${data.aws_region.current.region}:${data.aws_caller_identity.current.account_id}:file-system/${module.efs_file_system.file_system_id}",
          "arn:aws:s3:::${module.s3_bucket.bucket_name}",
        ]
      }
      nestedRestoreJobs              = {}
      restoreKubernetesManifestsOnly = false
      namespaceLevelRestore          = false
    })
    new_cluster = jsonencode({
      clusterName            = "restored-${var.primary_cluster_name}"
      newCluster             = true
      kubernetesRestoreOrder = []
      namespaces             = []
      namespacePvMapping = {
        (var.workload_namespace) = [
          "arn:aws:elasticfilesystem:${data.aws_region.current.region}:${data.aws_caller_identity.current.account_id}:file-system/${module.efs_file_system.file_system_id}",
          "arn:aws:s3:::${module.s3_bucket.bucket_name}",
        ]
      }
      nestedRestoreJobs              = {}
      restoreKubernetesManifestsOnly = false
      namespaceLevelRestore          = false
      # Only a new-cluster restore needs these: AWS Backup is building the cluster, so it needs the
      # same inputs a create-cluster call would.
      eksClusterVersion = var.kubernetes_version
      clusterRole       = module.primary_cluster.cluster_role_arn
      clusterVpcConfig = {
        vpcId            = module.network.vpc_id
        subnetIds        = concat(module.network.public_subnet_ids, module.network.private_subnet_ids)
        securityGroupIds = []
      }
      nodeGroups = [{
        nodeGroupId   = var.node_group_name
        subnetIds     = module.network.private_subnet_ids
        nodeRole      = module.eks_node_group.node_role_arn
        instanceTypes = var.node_instance_types
      }]
      fargateProfiles         = []
      podIdentityAssociations = []
    })
  }
}

locals {
  # Every output this project exposes, defined once. outputs.tf projects these and the README below
  # renders them, so no value expression is written twice (rules.md B-5/H-2). Adding an entry here is
  # what makes an output possible, which is what keeps the README from falling behind outputs.tf.
  outputs = {
    vscode_url = {
      order       = 1
      title       = "code-server"
      description = "Open the IDE here and run every command below from its terminal. The kubeconfig already has both clusters as contexts named primary and secondary"
      value       = module.vscode_ec2.vscode_url
    }
    primary_cluster_name = {
      order       = 2
      title       = "Primary cluster"
      description = "The cluster the backup is taken of. Everything Terraform creates inside a cluster is here"
      value       = module.primary_cluster.cluster_name
    }
    secondary_cluster_name = {
      order       = 3
      title       = "Secondary cluster (restore target)"
      description = "Deliberately empty - no addons, no capacity, no objects. AWS Backup writes into it, and anything Terraform put there would be a second owner of what a restore is about to replace"
      value       = var.create_secondary_cluster ? module.secondary_cluster[0].cluster_name : "create_secondary_cluster is false, so restore into a new cluster AWS Backup creates instead"
    }
    backup_vault_name = {
      order       = 4
      title       = "Backup vault"
      description = "Name-prefixed rather than fixed. The original hardcoded the vault as \"eks\", and a vault cannot be renamed - so a second copy of the project in one account collided permanently"
      value       = module.eks_backup_vault.vault_name
    }
    backup_role_arn = {
      order       = 5
      title       = "AWS Backup role"
      description = "The role AWS Backup assumes. It carries the S3 backup and restore policies as well as the EKS ones, because an EKS recovery point has a child for every attached volume - including a bucket"
      value       = module.eks_backup_vault.backup_role_arn
    }
    workloads_ready_command = {
      order       = 6
      title       = "1. Everything that should be backed up is running"
      description = "Three volume-backed Deployments, a bare Pod, a node-selected Deployment and five RBAC objects. None of these existed in the original: every manifest was applied by a user-data script that stopped at an `exec bash` several lines earlier"
      value       = module.backup_target_workloads.rollout_status_command
    }
    claims_bound_command = {
      order       = 7
      title       = "2. The claims are bound"
      description = "AWS Backup captures a volume only when its claim is provisioned by a CSI driver. The EBS claim stays Pending until a pod is scheduled, which is WaitForFirstConsumer working rather than failing"
      value       = module.backup_target_workloads.claim_status_command
    }
    volume_contents_command = {
      order       = 8
      title       = "3. There is data on the volumes"
      description = "What a restore is checked against. A recovery point taken before these pods wrote anything restores empty volumes, which is exactly what the original produced"
      value       = module.backup_target_workloads.volume_contents_command
    }
    start_backup_command = {
      order       = 9
      title       = "4. Take another backup"
      description = "The apply already started one of these and waited for it, so the vault holds a recovery point before anyone runs anything - the original did the same, and the scheduled plan is for keeping backups happening rather than for the first one. Run this again after changing the workloads, to get a second recovery point to compare a restore against"
      value       = local.start_backup_command
    }
    recovery_points_command = {
      order       = 10
      title       = "5. Find the composite recovery point"
      description = "One EKS backup produces several rows: a composite parent for the cluster state and a child for each attached volume - three of them here, for the EBS volume, the EFS file system and the S3 bucket. The parent is the ARN a restore takes, and it is the one containing \"composite:eks\""
      value       = module.eks_backup_vault.recovery_points_command
    }
    restore_metadata_existing = {
      order       = 11
      title       = "6a. Restore into the existing secondary cluster"
      description = "The metadata document with everything Terraform knows already filled in. Add the recovery point ARN, and a nestedRestoreJobs entry per child recovery point - see manifests/ in this project for a captured example of the finished article. The original left two placeholder markers here"
      value       = "aws backup start-restore-job --resource-type EKS --iam-role-arn ${module.eks_backup_vault.backup_role_arn} --recovery-point-arn <composite-arn> --metadata file:///home/ec2-user/restore/existing-cluster.json"
    }
    restore_metadata_new = {
      order       = 12
      title       = "6b. Restore into a cluster AWS Backup creates"
      description = "The same call with newCluster true. This document also carries the cluster role, VPC config and node group definition, which is why a new-cluster restore can recreate managed node groups, Fargate profiles, addons and Pod Identity associations - and why it cannot recreate the OIDC provider or any ECR image"
      value       = "aws backup start-restore-job --resource-type EKS --iam-role-arn ${module.eks_backup_vault.backup_role_arn} --recovery-point-arn <composite-arn> --metadata file:///home/ec2-user/restore/new-cluster.json"
    }
    restore_result_command = {
      order       = 13
      title       = "7. What the restore actually produced"
      description = "Run against the secondary context. Services and Ingresses are never restored, and pods matching a nodeSelector the target cluster's nodes do not carry stay Pending - both are expected"
      value       = "kubectl --context secondary -n ${var.workload_namespace} get deployments,pods,pvc,serviceaccounts,roles,rolebindings"
    }
    skipped_objects_command = {
      order       = 14
      title       = "8. What the restore skipped"
      description = "A restore job reports COMPLETED even when it skipped objects. The list exists only as vault notifications, which is what the topic and queue are for - and the queue policy that lets SNS deliver to it was missing in the original, so the queue stayed empty"
      value       = module.eks_backup_vault.skipped_objects_command
    }
    backup_plan_id = {
      order       = 15
      title       = "Backup plan"
      description = "A scheduled plan covering the primary cluster, which the original did not have: it started one job from a shell and left it there, so the cluster had exactly one recovery point for as long as it existed. The plan is what makes a backup a property of the configuration; the job the apply starts is what makes the demo runnable before the plan's first 03:00 UTC run"
      value       = var.create_backup_plan ? module.eks_backup_vault.backup_plan_id : "create_backup_plan is false, so backups only happen when started by hand"
    }
    update_kubeconfig_command = {
      order       = 16
      title       = "Re-point kubectl"
      description = "User data already wrote both contexts. Re-run these if the kubeconfig is ever lost"
      value       = "aws eks update-kubeconfig --region ${data.aws_region.current.region} --name ${module.primary_cluster.cluster_name} --alias primary"
    }
  }
  # Iterating local.outputs directly would order sections by key. Re-keying by the order field and
  # taking values() sorts by that instead - values() returns a map's values ordered by key - so the
  # README reads in the order the demo is run.
  readme_ordered = values({
    for key, entry in local.outputs : format("%02d-%s", entry.order, key) => entry
  })
  readme_body = join("\n", concat(
    ["# ${var.project_name}", ""],
    flatten([for entry in local.readme_ordered : [
      "## ${entry.title}", "", entry.description, "", "```", entry.value, "```", "",
    ]]),
  ))
}

# The work happens inside code-server in a browser, where "terraform output" does not exist, so every
# output above is also written to a README in the home directory the IDE opens (rules.md H-2).
#
# This association also writes the two restore metadata documents as files, for the same reason
# 030_emr_on_eks delivers its job definitions as files: a JSON document of this size does not survive
# being pasted into a shell, and `--metadata file://...` takes it directly.
resource "aws_ssm_association" "vscode_readme" {
  name                             = "AWS-RunShellScript"
  wait_for_success_timeout_seconds = var.readme_timeout_seconds
  targets {
    key    = "InstanceIds"
    values = [module.vscode_ec2.instance_id]
  }
  parameters = {
    # The until loop, not depends_on, is what orders this after the instance bootstrap - the marker is
    # written as the last line of user data. The original used `sleep 180`, which is the same bet
    # against a slower boot (rules.md D-5).
    #
    # SSM runs as root, hence the chown. Each heredoc delimiter is quoted and deliberately unlikely to
    # appear in its body: Terraform has already substituted every value, so the shell has no reason to
    # touch a "$" or a backtick - and the README's commands contain both.
    commands = <<-EOT
      set -euo pipefail
      until [ -f ${module.vscode_ec2.marker_file_path}/userdata ]; do sleep 10; done
      mkdir -p /home/ec2-user/restore
      cat > /home/ec2-user/restore/existing-cluster.json << 'TFEXISTING'
      ${local.restore_metadata.existing_cluster}
      TFEXISTING
      cat > /home/ec2-user/restore/new-cluster.json << 'TFNEW'
      ${local.restore_metadata.new_cluster}
      TFNEW
      cat > /home/ec2-user/README.md << 'TFREADME'
      ${local.readme_body}
      TFREADME
      chown -R ec2-user:ec2-user /home/ec2-user/README.md /home/ec2-user/restore
      touch ${module.vscode_ec2.marker_file_path}/vscode_readme
      EOT
  }
}

# The first recovery point, taken during the apply.
#
# The _monolithic template did this too - `aws backup start-backup-job` from an SSM Association - and
# the modularized configuration dropped it in favour of the scheduled plan alone. The reason recorded
# for dropping it was that the original's job captured an empty cluster, which was true: its user data
# hit an `exec bash` before any `kubectl apply` ran, so there was nothing in the cluster to capture.
# That is a story about the original's ordering, not about starting a job during an apply.
# module.eks_backup_vault is ordered after module.backup_target_workloads, so by the time this runs the
# workloads exist and their volumes have been written to.
#
# What the plan alone could not do is leave the project demonstrable. Every step of the README from
# "find the composite recovery point" onwards needs a recovery point, and the plan's first run is up to
# a day away - so an apply finished with an empty vault and nothing saying why.
#
# No AWS provider resource starts a backup job, so this is a CLI call like the original's. It is the
# same string the README hands the operator (rules.md B-5), and the instance already carries the CLI and
# an instance role broad enough to call it (rules.md H-1).
resource "aws_ssm_association" "start_backup" {
  count = var.start_backup_on_apply ? 1 : 0

  name = "AWS-RunShellScript"
  # Has to outlast the script's own polling budget below. If SSM gives up first, all that is reported is
  # "unexpected state 'Failed'" with no job id in it, and the backup is left running where nothing is
  # watching it (rules.md A-4). Derived from that budget rather than being a second variable, so the two
  # cannot be given a contradictory pair of values (rules.md B-1).
  wait_for_success_timeout_seconds = var.backup_job_timeout_seconds + 600
  targets {
    key    = "InstanceIds"
    values = [module.vscode_ec2.instance_id]
  }
  parameters = {
    commands = <<-EOT
      set -euo pipefail
      until [ -f ${module.vscode_ec2.marker_file_path}/vscode_readme ]; do sleep 10; done
      # SSM runs as root, and user data configured a default region for ec2-user only, so the region is
      # passed in here rather than left to whatever the CLI can infer from the instance.
      export AWS_DEFAULT_REGION=${data.aws_region.current.region}
      job_id=$(${local.start_backup_command} --query BackupJobId --output text)
      echo "started backup job $job_id"
      deadline=$(( $(date +%s) + ${var.backup_job_timeout_seconds} ))
      while :; do
        state=$(aws backup describe-backup-job --backup-job-id "$job_id" --query State --output text)
        case "$state" in
          # PARTIAL is finished, not failed. An EKS backup job reports Completed, Partial or Failed, and
          # a partial job still produces a usable composite recovery point - what it could not capture
          # is listed in the vault's notifications, which is what the topic and queue are for. Failing
          # the apply on it would turn an outcome this project exists to show into an error.
          COMPLETED|PARTIAL)
            echo "backup job $job_id finished as $state"
            break
            ;;
          FAILED|ABORTED|EXPIRED)
            aws backup describe-backup-job --backup-job-id "$job_id" >&2
            echo "backup job $job_id ended as $state" >&2
            exit 1
            ;;
        esac
        if [ "$(date +%s)" -ge "$deadline" ]; then
          aws backup describe-backup-job --backup-job-id "$job_id" >&2
          echo "backup job $job_id was still $state after ${var.backup_job_timeout_seconds}s" >&2
          exit 1
        fi
        sleep 15
      done
      touch ${module.vscode_ec2.marker_file_path}/start_backup
      EOT
  }

  # Chained behind the README association rather than run alongside it, so two associations are not
  # executing on the same instance at once and the marker chain stays a chain (rules.md D-5). Everything
  # this needs from AWS arrives through local.start_backup_command.
  depends_on = [aws_ssm_association.vscode_readme]
}
