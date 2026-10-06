variable "aws_region" {
  type        = string
  default     = null
  description = "Target AWS region. Null falls through to the provider chain (AWS_REGION / AWS_DEFAULT_REGION)"

  validation {
    condition     = var.aws_region == null || can(regex("^[a-z]{2}(-[a-z]+)+-[0-9]$", var.aws_region))
    error_message = "aws_region must be a valid AWS region name (e.g. ap-northeast-2), or null."
  }
}

variable "project_name" {
  type        = string
  default     = "eks-backup-nodegroup"
  description = "Prefix for resource names that have to be unique inside the account, and the title of the README written onto the workbench"

  validation {
    condition     = can(regex("^[a-z0-9][a-z0-9-]{1,30}[a-z0-9]$", var.project_name))
    error_message = "project_name must be 3-32 lowercase letters, digits or hyphens and must not start or end with a hyphen."
  }
}

# --- Network ---

variable "vpc_cidr_block" {
  type        = string
  default     = "10.0.0.0/16"
  description = "CIDR block of the VPC. One VPC for both clusters, as the _monolithic template had it - a restore into a cluster in the same VPC can reuse the same subnets and the same EFS mount targets"

  validation {
    condition     = can(cidrhost(var.vpc_cidr_block, 0))
    error_message = "vpc_cidr_block must be a valid IPv4 CIDR block."
  }
}

variable "availability_zone_suffixes" {
  type        = list(string)
  default     = ["a", "c"]
  description = "Availability zones the VPC spans, by suffix. Two - a and c - exactly the pair the _monolithic template's AzMapping defined"

  validation {
    condition     = length(var.availability_zone_suffixes) >= 2
    error_message = "availability_zone_suffixes must name at least two zones; an EKS control plane requires subnets in two."
  }
}

variable "nat_availability_zone_suffixes" {
  type        = list(string)
  default     = ["a", "c"]
  description = "Zones the regional NAT gateway is given an address in. One Elastic IP per entry, as the _monolithic template allocated two"

  validation {
    condition     = length(setsubtract(var.nat_availability_zone_suffixes, var.availability_zone_suffixes)) == 0
    error_message = "nat_availability_zone_suffixes must be drawn from availability_zone_suffixes; an address in a zone with no subnet is routed nowhere."
  }
}

# --- The two clusters ---

variable "primary_cluster_name" {
  type        = string
  default     = "primary-cluster"
  description = "Name of the cluster the backup is taken of, as the _monolithic template named it. Everything Terraform creates inside a cluster goes into this one"

  validation {
    condition     = can(regex("^[a-zA-Z0-9][a-zA-Z0-9-_]{0,99}$", var.primary_cluster_name))
    error_message = "primary_cluster_name must start with a letter or digit and contain only letters, digits, hyphens and underscores."
  }
}

variable "secondary_cluster_name" {
  type        = string
  default     = "secondary-cluster"
  description = <<-DESC
    Name of the restore target cluster, as the _monolithic template named it.

    Deliberately empty: no addons, no capacity, no Kubernetes objects. AWS Backup writes into it, and an
    object Terraform created there would be a second owner of something a restore is about to replace.
    The one thing it does need from Terraform is an access entry for the backup role, which the
    _monolithic template left to two commands in its README.
  DESC

  validation {
    condition     = can(regex("^[a-zA-Z0-9][a-zA-Z0-9-_]{0,99}$", var.secondary_cluster_name))
    error_message = "secondary_cluster_name must start with a letter or digit and contain only letters, digits, hyphens and underscores."
  }
}

variable "create_secondary_cluster" {
  type        = bool
  default     = true
  description = "Whether to create the restore target cluster. True reproduces the _monolithic template; false halves the control plane cost while leaving the backup half of the demo intact, since a restore can also target a new cluster AWS Backup creates itself"
}

variable "kubernetes_version" {
  type        = string
  default     = "1.34"
  description = "Kubernetes version for both clusters. A restore into an existing cluster needs the target at the same version or newer, which is why one variable feeds both"

  validation {
    condition     = can(regex("^1\\.[0-9]+$", var.kubernetes_version))
    error_message = "kubernetes_version must look like 1.XX; the cluster module holds the list of versions this project is verified against."
  }
}

variable "authentication_mode" {
  type        = string
  default     = "API_AND_CONFIG_MAP"
  description = <<-DESC
    Cluster authentication mode, as the _monolithic template set it.

    Not a free choice here. AWS Backup creates its own access entry on the cluster it backs up, and an
    access entry needs API or API_AND_CONFIG_MAP - with CONFIG_MAP the backup job fails on a permission
    it cannot grant itself, and the project's own notes list this as a requirement.
  DESC

  validation {
    condition     = contains(["API", "API_AND_CONFIG_MAP"], var.authentication_mode)
    error_message = "authentication_mode must be API or API_AND_CONFIG_MAP. AWS Backup creates access entries to reach the cluster, and CONFIG_MAP alone does not support them (rules.md B-1)."
  }
}

variable "endpoint_public_access" {
  type        = bool
  default     = true
  description = "Whether the clusters' API servers have a public endpoint. True here, and pinned true, because the backup target objects are applied by the kubectl provider running on the machine executing terraform"

  validation {
    # Not a free choice: this root declares kubectl and helm providers, and those run wherever
    # terraform runs. With a private-only endpoint they cannot connect, plan still passes, and the
    # failure appears mid-apply as a dial timeout that looks exactly like the destroy-ordering problem
    # rules.md D-4 describes (rules.md E-9).
    condition     = var.endpoint_public_access
    error_message = "endpoint_public_access must be true in this variant, because the backup target objects and the Helm release are applied by providers running on the machine executing terraform. To run with a private endpoint, drop those providers and apply everything from the workbench through SSM Associations instead, as 041_eks_private_cluster does."
  }
}

variable "public_access_cidrs" {
  type        = list(string)
  default     = ["0.0.0.0/0"]
  description = "CIDRs allowed to reach the public API server endpoints. Narrow this for anything longer lived than a demo"

  validation {
    condition     = alltrue([for cidr in var.public_access_cidrs : can(cidrhost(cidr, 0))])
    error_message = "public_access_cidrs must contain valid IPv4 CIDR blocks."
  }
}

variable "cluster_log_types" {
  type        = list(string)
  default     = ["api", "audit", "authenticator", "controllerManager", "scheduler"]
  description = "Control plane logs sent to CloudWatch, as the _monolithic template enabled them. All five, which is also where a rejected AWS Backup call to the API server is visible"

  validation {
    condition     = alltrue([for t in var.cluster_log_types : contains(["api", "audit", "authenticator", "controllerManager", "scheduler"], t)])
    error_message = "cluster_log_types must be drawn from api, audit, authenticator, controllerManager and scheduler."
  }
}

variable "coredns_replica_count" {
  type        = number
  default     = 2
  description = "Number of CoreDNS replicas on the primary cluster"

  validation {
    condition     = var.coredns_replica_count >= 1
    error_message = "coredns_replica_count must be at least 1."
  }
}

# --- Node group ---

variable "node_group_name" {
  type        = string
  default     = "app-mng"
  description = "Name of the managed node group, as the _monolithic template named it. A restore into a new cluster recreates the node group under this name, so it also appears in the restore metadata"

  validation {
    condition     = can(regex("^[a-zA-Z0-9][a-zA-Z0-9-_]{0,62}$", var.node_group_name))
    error_message = "node_group_name must start with a letter or digit and contain only letters, digits, hyphens and underscores."
  }
}

variable "node_instance_types" {
  type        = list(string)
  default     = ["t3.large"]
  description = "Instance types for the managed node group, as the _monolithic template sized them"

  validation {
    condition     = length(var.node_instance_types) > 0
    error_message = "node_instance_types must contain at least one instance type."
  }
}

variable "node_desired_size" {
  type        = number
  default     = 2
  description = "Desired node count"

  validation {
    condition     = var.node_desired_size >= 1
    error_message = "node_desired_size must be at least 1."
  }
}

variable "node_min_size" {
  type        = number
  default     = 2
  description = "Minimum node count"

  validation {
    condition     = var.node_min_size >= 1
    error_message = "node_min_size must be at least 1."
  }
}

variable "node_max_size" {
  type        = number
  default     = 4
  description = "Maximum node count"

  validation {
    condition     = var.node_max_size >= 1
    error_message = "node_max_size must be at least 1."
  }
}

variable "node_labels" {
  type        = map(string)
  default     = { nodegroup = "app" }
  description = "Labels on the node group's nodes, as the _monolithic template set them. The node-selected Deployment below matches on these, which makes a restore into a cluster without them visibly leave pods Pending"
}

# --- AWS Load Balancer Controller ---

variable "load_balancer_controller_chart_version" {
  type        = string
  default     = "1.14.1"
  description = <<-DESC
    Pinned aws-load-balancer-controller chart version.

    The _monolithic template created this controller's IAM role and Pod Identity association and then
    installed nothing: its `helm install` sat after an `exec bash` in the workbench's user data, which
    replaces the shell and discards every remaining line. The role existed, attached to nothing.
  DESC

  validation {
    condition     = can(regex("^[0-9]+\\.[0-9]+\\.[0-9]+$", var.load_balancer_controller_chart_version))
    error_message = "load_balancer_controller_chart_version must be a three-part semantic version."
  }
}

variable "install_load_balancer_controller" {
  type        = bool
  default     = true
  description = "Whether to install the load balancer controller. Nothing here creates an Ingress - AWS Backup cannot restore Services or Ingresses at all, which the project's own notes record - so this exists to make the IAM role and Pod Identity association the _monolithic template created mean something, and to give the restore metadata a Pod Identity association to carry"
}

# --- Backup vault ---

variable "create_backup_plan" {
  type        = bool
  default     = true
  description = "Whether to create a scheduled backup plan covering the primary cluster. True, so backups keep happening rather than existing only as the single job start_backup_on_apply takes - which is all the _monolithic template had"
}

variable "start_backup_on_apply" {
  type        = bool
  default     = true
  description = <<-DESC
    Whether the apply starts one backup job of the primary cluster and waits for it, in addition to
    creating the scheduled plan.

    True, and this restores something the _monolithic template did. It ran `aws backup start-backup-job`
    from an SSM Association, and the modularized configuration dropped that in favour of the plan alone,
    on the grounds that the original's job captured an empty cluster. That was true, but it was a
    consequence of the original's `exec bash` bug - no workload was ever created, so there was nothing
    to capture - rather than of starting a job during the apply. Here the vault module is ordered after
    module.backup_target_workloads, so the job captures a populated cluster.

    Without it the project cannot be demonstrated after an apply: every step from "find the composite
    recovery point" onwards needs a recovery point to exist, and the plan's first run is up to a day
    away, since the default schedule is 03:00 UTC.
  DESC
}

variable "backup_job_timeout_seconds" {
  type        = number
  default     = 3600
  description = "How long the apply waits for the backup job it started. Measured at 33 minutes on this variant, so an hour leaves headroom: the composite parent walks the cluster's objects and spawns a child job per attached volume - four here, for the cluster state, an EBS volume, an EFS file system and an S3 bucket - and it keeps running for some minutes after the last child has reported COMPLETED. The Fargate variant, with one child, finishes in under ten. Too low a value fails the apply on a backup that was going to succeed, and the give-away is a describe-backup-job in the association output showing every child COMPLETED under a parent still RUNNING. The wait itself is the point: it makes a failed backup fail the apply, rather than leaving an empty vault to be found later by someone who assumed the apply had taken one"

  validation {
    condition     = var.backup_job_timeout_seconds >= 300 && var.backup_job_timeout_seconds <= 28800
    error_message = "backup_job_timeout_seconds must be between 300 and 28800 - eight hours being the plan's own completion window, beyond which AWS Backup aborts the job anyway."
  }
}

variable "backup_schedule" {
  type        = string
  default     = "cron(0 3 * * ? *)"
  description = "Cron expression for the plan, in UTC"

  validation {
    condition     = can(regex("^(cron|rate)\\(", var.backup_schedule))
    error_message = "backup_schedule must be a cron() or rate() expression."
  }
}

variable "backup_delete_after_days" {
  type        = number
  default     = 7
  description = "How long a recovery point is kept. Short by default: a composite EKS recovery point keeps every child snapshot alive with it"

  validation {
    condition     = var.backup_delete_after_days >= 1
    error_message = "backup_delete_after_days must be at least 1."
  }
}

variable "restore_access_policy_arn" {
  type        = string
  default     = "arn:aws:eks::aws:cluster-access-policy/AWSBackupFullAccessPolicyForRestore"
  description = <<-DESC
    Cluster access policy associated with the backup role on the restore target cluster.

    This is the pair of resources the _monolithic template put in its README as two commands for a person
    to run - `aws eks create-access-entry` and `aws eks associate-access-policy`. Without them a restore
    into the secondary cluster is rejected for a permission nothing in the configuration mentions.

    AWS Backup creates its own access entry on the cluster it *backs up*; the target of a restore is not
    that cluster, so nothing creates one there.
  DESC

  validation {
    condition     = can(regex("^arn:aws:eks::aws:cluster-access-policy/", var.restore_access_policy_arn))
    error_message = "restore_access_policy_arn must be an EKS cluster access policy ARN."
  }
}

# --- Storage the backup captures ---

variable "efs_performance_mode" {
  type        = string
  default     = "generalPurpose"
  description = "EFS performance mode, as the _monolithic template set it"

  validation {
    condition     = contains(["generalPurpose", "maxIO"], var.efs_performance_mode)
    error_message = "efs_performance_mode must be generalPurpose or maxIO."
  }
}

variable "s3_bucket_prefix" {
  type        = string
  default     = "eks-backup-"
  description = "Prefix for the generated bucket name. A prefix rather than a name because a bucket name is global to all of AWS - the _monolithic template declared aws_s3_bucket with no arguments at all, leaving the provider to invent one"

  validation {
    condition     = can(regex("^[a-z0-9][a-z0-9.-]{1,36}$", var.s3_bucket_prefix))
    error_message = "s3_bucket_prefix must be 2-37 lowercase characters valid in a bucket name; the provider appends a suffix."
  }
}

variable "s3_bucket_force_destroy" {
  type        = bool
  default     = true
  description = "Whether `terraform destroy` empties the bucket first. True for a demo: the Mountpoint-backed pod writes objects into it, and S3 refuses to delete a bucket with anything in it"
}

variable "ebs_volume_type" {
  type        = string
  default     = "io1"
  description = "EBS volume type the demo StorageClass provisions, as the _monolithic template set it. io1 bills for provisioned IOPS whether they are used or not, so gp3 is the better choice for anything left running"

  validation {
    condition     = contains(["gp2", "gp3", "io1", "io2"], var.ebs_volume_type)
    error_message = "ebs_volume_type must be gp2, gp3, io1 or io2."
  }
}

variable "workload_namespace" {
  type        = string
  default     = "default"
  description = "Namespace the backup target objects live in, as the _monolithic template placed them. Also the key of the namespacePvMapping entry in the restore metadata"

  validation {
    condition     = can(regex("^[a-z0-9]([-a-z0-9]*[a-z0-9])?$", var.workload_namespace))
    error_message = "workload_namespace must be a valid lowercase RFC 1123 label."
  }
}

# --- Workbench instance ---

variable "vscode_instance_type" {
  type        = string
  default     = "t3.medium"
  description = "Instance type of the code-server workbench, as the _monolithic template sized it"

  validation {
    condition     = can(regex("^[a-z0-9]+\\.[a-z0-9]+$", var.vscode_instance_type))
    error_message = "vscode_instance_type must look like an EC2 instance type (e.g. t3.medium)."
  }
}

variable "allow_inbound_from_anywhere" {
  type        = bool
  default     = true
  description = "Whether the workbench security group accepts code-server traffic from 0.0.0.0/0. True reproduces the _monolithic template's InboundFromAnywhere default; code-server runs with auth disabled, so restrict this for anything beyond a demo"
}

variable "kubectl_download_version" {
  type        = string
  default     = "1.34.11/2026-09-22"
  description = "kubectl build downloaded onto the workbench, as <version>/<release-date>. Kept within one minor of kubernetes_version; the _monolithic template pinned a 1.33 build against a 1.34 cluster"

  validation {
    condition     = can(regex("^1\\.[0-9]+\\.[0-9]+/[0-9]{4}-[0-9]{2}-[0-9]{2}$", var.kubectl_download_version))
    error_message = "kubectl_download_version must look like 1.34.11/2026-09-22."
  }
}

variable "code_server_version" {
  type        = string
  default     = "4.108.2"
  description = "code-server release installed on the workbench"

  validation {
    condition     = can(regex("^[0-9]+\\.[0-9]+\\.[0-9]+$", var.code_server_version))
    error_message = "code_server_version must be a three-part semantic version."
  }
}

variable "marker_file_path" {
  type        = string
  default     = "/run/terraform"
  description = "Directory on the workbench where each bootstrap stage drops its completion marker. The _monolithic template used `sleep 180` instead, which is the same bet with worse odds (rules.md D-5)"

  validation {
    condition     = can(regex("^/", var.marker_file_path))
    error_message = "marker_file_path must be an absolute path starting with '/'."
  }
}

variable "readme_timeout_seconds" {
  type        = number
  default     = 1800
  description = "How long the README association waits for success"

  validation {
    condition     = var.readme_timeout_seconds >= 300
    error_message = "readme_timeout_seconds must be at least 300."
  }
}
