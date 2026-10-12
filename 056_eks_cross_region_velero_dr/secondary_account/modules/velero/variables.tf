variable "cluster_name" {
  type        = string
  description = "Name of the EKS cluster Velero runs on. Used to scope the Pod Identity association, which is the only cluster-specific thing in this module - the IAM role itself is reusable across clusters"

  validation {
    condition     = length(var.cluster_name) > 0
    error_message = "cluster_name must not be empty."
  }
}
variable "bucket_name" {
  type        = string
  description = "Name of the S3 bucket backups go to. Taken from the bucket module's output rather than restated, so the BackupStorageLocation cannot point at a bucket that was never created (rules.md B-5)"

  validation {
    condition     = can(regex("^[a-z0-9][a-z0-9.-]{1,61}[a-z0-9]$", var.bucket_name))
    error_message = "bucket_name must be a valid S3 bucket name."
  }
}
variable "bucket_arn" {
  type        = string
  description = "ARN of the same bucket, used to scope the Velero role's object permissions to it. Taken separately rather than derived from the name, because deriving it would put a second, independent definition of the bucket's identity in this module"

  validation {
    condition     = can(regex("^arn:aws:s3:::", var.bucket_arn))
    error_message = "bucket_arn must be an S3 bucket ARN (arn:aws:s3:::<name>)."
  }
}
variable "bucket_region" {
  type        = string
  description = "Region the bucket is in, for the BackupStorageLocation's config. The bucket's region, not the cluster's - these differ in the cross-account variants, where the whole point is that the backup lands somewhere else. A wrong value fails every backup with an S3 redirect error that names no bucket"

  validation {
    condition     = can(regex("^[a-z]{2}(-[a-z]+)+-[0-9]$", var.bucket_region))
    error_message = "bucket_region must be an AWS region code (e.g. ap-northeast-2)."
  }
}
variable "snapshot_region" {
  type        = string
  description = "Region the EBS snapshots are taken in, for the VolumeSnapshotLocation's config. The cluster's region, because snapshots are taken where the volumes are - only the backup metadata and the moved data go to the bucket. These two being equal in the _monolithic template was a consequence of everything sharing one region, not a rule (rules.md I-3)"

  validation {
    condition     = can(regex("^[a-z]{2}(-[a-z]+)+-[0-9]$", var.snapshot_region))
    error_message = "snapshot_region must be an AWS region code (e.g. ap-northeast-2)."
  }
}
variable "role_name" {
  type        = string
  default     = null
  description = "Optional fixed name for Velero's IAM role. Null generates one from role_name_prefix, which is what lets this project be deployed twice in one account"

  validation {
    condition     = var.role_name == null || can(regex("^[a-zA-Z0-9+=,.@_-]{1,64}$", var.role_name))
    error_message = "role_name must be 1-64 characters of the set IAM accepts for a role name, or null."
  }
}
variable "role_name_prefix" {
  type        = string
  default     = "velero-"
  description = "Prefix for the generated role name when role_name is null"

  validation {
    condition     = can(regex("^[a-zA-Z0-9+=,.@_-]{1,32}$", var.role_name_prefix))
    error_message = "role_name_prefix must be 1-32 characters of the set IAM accepts for a role name."
  }
}
variable "namespace" {
  type        = string
  default     = "velero"
  description = "Namespace Velero runs in, as the _monolithic template's velero install default had it. Created by the release, and also the namespace the Pod Identity association is scoped to"

  validation {
    condition     = can(regex("^[a-z0-9]([-a-z0-9]*[a-z0-9])?$", var.namespace))
    error_message = "namespace must be a valid lowercase RFC 1123 DNS label."
  }
}
variable "service_account_name" {
  type        = string
  default     = "velero"
  description = "Service account Velero runs as. The chart creates it and the Pod Identity association binds it, so this one variable decides both sides"

  validation {
    condition     = can(regex("^[a-z0-9]([-a-z0-9.]*[a-z0-9])?$", var.service_account_name))
    error_message = "service_account_name must be a valid lowercase RFC 1123 subdomain."
  }
}
variable "release_name" {
  type        = string
  default     = "velero"
  description = "Helm release name"

  validation {
    condition     = can(regex("^[a-z0-9]([-a-z0-9]*[a-z0-9])?$", var.release_name))
    error_message = "release_name must be a valid lowercase RFC 1123 DNS label."
  }
}
variable "chart_repository" {
  type        = string
  default     = "https://vmware-tanzu.github.io/helm-charts"
  description = "Velero's official chart repository. The _monolithic template used the velero CLI instead, which pins nothing and leaves the BackupStorageLocation outside Terraform state"

  validation {
    condition     = can(regex("^https://", var.chart_repository))
    error_message = "chart_repository must be an https URL."
  }
}
variable "chart_version" {
  type        = string
  default     = "12.2.0"
  description = "Pinned chart version. Chart 12.2.0 carries Velero 1.18.2, where the _monolithic template installed the CLI at v1.17.0 - and the chart's version is not the app's, which is worth checking before bumping it. The plugin has to be bumped in step (see plugin_image_tag)"

  validation {
    condition     = can(regex("^[0-9]+\\.[0-9]+\\.[0-9]+$", var.chart_version))
    error_message = "chart_version must be a semantic version (e.g. 12.2.0)."
  }
}
variable "plugin_image_repository" {
  type        = string
  default     = "velero/velero-plugin-for-aws"
  description = "Repository for the AWS plugin's init container image. The plugin is what gives Velero its S3 object store and its EBS volume snapshotter; the chart ships none by default"

  validation {
    condition     = length(var.plugin_image_repository) > 0
    error_message = "plugin_image_repository must not be empty."
  }
}
variable "plugin_image_tag" {
  type        = string
  default     = "v1.14.3"
  description = "Plugin version, which has to match the Velero version the chart carries: the plugin's compatibility table pairs v1.14.x with Velero v1.18.x. The _monolithic template used v1.13.0 against a CLI at v1.17.0, which was the correct pair for that version - the pairing is the thing to preserve when either is bumped, not either version on its own"

  validation {
    condition     = can(regex("^v[0-9]+\\.[0-9]+\\.[0-9]+$", var.plugin_image_tag))
    error_message = "plugin_image_tag must be a v-prefixed semantic version (e.g. v1.14.3)."
  }
}
variable "backup_storage_location_name" {
  type        = string
  default     = "default"
  description = "Name of the BackupStorageLocation. default as Velero itself would name it, and the name a backup uses when none is given"

  validation {
    condition     = can(regex("^[a-z0-9]([-a-z0-9]*[a-z0-9])?$", var.backup_storage_location_name))
    error_message = "backup_storage_location_name must be a valid lowercase RFC 1123 DNS label."
  }
}
variable "volume_snapshot_location_name" {
  type        = string
  default     = "default"
  description = "Name of the VolumeSnapshotLocation"

  validation {
    condition     = can(regex("^[a-z0-9]([-a-z0-9]*[a-z0-9])?$", var.volume_snapshot_location_name))
    error_message = "volume_snapshot_location_name must be a valid lowercase RFC 1123 DNS label."
  }
}
variable "features" {
  type        = list(string)
  default     = ["EnableCSI"]
  description = "Velero feature flags, as the _monolithic template's --features EnableCSI had it. EnableCSI is what makes Velero back up a volume through its VolumeSnapshot object; without it a backup of the demo StatefulSet completes having captured the Kubernetes objects and none of the volume data - which reports as success"

  validation {
    condition     = length(var.features) > 0
    error_message = "features must contain at least one flag; EnableCSI is what this project depends on."
  }
}
variable "deploy_node_agent" {
  type        = bool
  default     = true
  description = "Whether to run the node agent DaemonSet, as the _monolithic template's --use-node-agent had it. This is what moves snapshot data into the bucket: a backup with --snapshot-move-data and no node agent completes having recorded only that a snapshot exists in the source region, so there is nothing in the bucket for the other cluster to restore from"
}
variable "timeout_seconds" {
  type        = number
  default     = 900
  description = "How long to wait for the Velero Deployment to become Available. Longer than a typical controller because the release also applies Velero's CRDs and runs the chart's CRD upgrade job first"

  validation {
    condition     = var.timeout_seconds > 0
    error_message = "timeout_seconds must be positive."
  }
}
