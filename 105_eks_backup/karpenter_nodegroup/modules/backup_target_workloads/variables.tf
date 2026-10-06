variable "namespace" {
  type        = string
  default     = "default"
  description = "Namespace the namespaced objects are created in, as the _monolithic template placed them"

  validation {
    condition     = can(regex("^[a-z0-9]([-a-z0-9]*[a-z0-9])?$", var.namespace))
    error_message = "namespace must be a valid lowercase RFC 1123 label."
  }
}

variable "aws_region" {
  type        = string
  description = "Region the Mountpoint volume is told to address the bucket in. Required because a bucket is reached regionally and the driver takes it as a mount option rather than discovering it"

  validation {
    condition     = can(regex("^[a-z]{2}(-[a-z]+)+-[0-9]$", var.aws_region))
    error_message = "aws_region must be a valid AWS region name."
  }
}

variable "replicas" {
  type        = number
  default     = 2
  description = "Replicas for each volume-backed Deployment, as the _monolithic template set them"

  validation {
    condition     = var.replicas >= 1
    error_message = "replicas must be at least 1."
  }
}

variable "volume_writer_image" {
  type        = string
  default     = "public.ecr.aws/amazonlinux/amazonlinux:2023"
  description = "Image the three volume-backed Deployments run. One image rather than the rockylinux:8, amazonlinux and ubuntu the _monolithic template used for the three - two of those come from Docker Hub, whose anonymous pull limit is shared by every node in the region and shows up as ImagePullBackOff with a \"toomanyrequests\" message"

  validation {
    condition     = can(regex("^[^\\s]+:[^\\s:]+$", var.volume_writer_image))
    error_message = "volume_writer_image must include an explicit tag."
  }
}

variable "web_image" {
  type        = string
  default     = "public.ecr.aws/nginx/nginx:stable"
  description = "Image the bare Pod and the node-selected Deployment run. From the ECR public gallery rather than Docker Hub's nginx, for the same pull-limit reason"

  validation {
    condition     = can(regex("^[^\\s]+:[^\\s:]+$", var.web_image))
    error_message = "web_image must include an explicit tag."
  }
}

# --- EFS ---

variable "create_efs_workload" {
  type        = bool
  default     = true
  description = "Whether to create the EFS StorageClass, claim and Deployment. EFS is the one volume kind every variant can have, Fargate included"
}

variable "efs_file_system_id" {
  type        = string
  default     = null
  description = "File system the StorageClass provisions access points in. Required when create_efs_workload is true"

  validation {
    condition     = var.efs_file_system_id == null || can(regex("^fs-[0-9a-f]+$", var.efs_file_system_id))
    error_message = "efs_file_system_id must be an EFS file system id (e.g. fs-0123456789abcdef0), or null."
  }

  validation {
    # The pair, not either value alone: a StorageClass with an empty fileSystemId is accepted and every
    # claim against it stays Pending with the reason only in the CSI controller's log (rules.md B-1).
    condition     = var.create_efs_workload == false || var.efs_file_system_id != null
    error_message = "efs_file_system_id is required when create_efs_workload is true, because the StorageClass names the file system it provisions access points in."
  }
}

variable "efs_storage_class_name" {
  type        = string
  default     = "efs-sc"
  description = "Name of the EFS StorageClass, as the _monolithic template named it. Its provisioner is what decides whether AWS Backup can protect the claim at all - an in-tree or CSI-migrated volume cannot be backed up, and the annotation on the volume does not tell you which it is"

  validation {
    condition     = can(regex("^[a-z0-9]([-a-z0-9.]*[a-z0-9])?$", var.efs_storage_class_name))
    error_message = "efs_storage_class_name must be a valid lowercase RFC 1123 subdomain."
  }
}

variable "efs_volume_size" {
  type        = string
  default     = "5Gi"
  description = "Requested size of the EFS claim, as the _monolithic template set it. EFS is elastic, so this is bookkeeping the API requires rather than a limit"

  validation {
    condition     = can(regex("^[0-9]+(Mi|Gi|Ti)$", var.efs_volume_size))
    error_message = "efs_volume_size must be a Kubernetes storage quantity (e.g. 5Gi)."
  }
}

# --- EBS ---

variable "create_ebs_workload" {
  type        = bool
  default     = true
  description = "Whether to create the EBS StorageClass, claim and Deployment. False on a Fargate-only cluster, which cannot attach a block device at all"
}

variable "ebs_storage_class_name" {
  type        = string
  default     = "ebs-sc"
  description = "Name of the EBS StorageClass, as the _monolithic template named it"

  validation {
    condition     = can(regex("^[a-z0-9]([-a-z0-9.]*[a-z0-9])?$", var.ebs_storage_class_name))
    error_message = "ebs_storage_class_name must be a valid lowercase RFC 1123 subdomain."
  }
}

variable "ebs_volume_type" {
  type        = string
  default     = "io1"
  description = "EBS volume type the class provisions, as the _monolithic template set it. io1 bills for provisioned IOPS whether they are used or not, so it is worth changing to gp3 for anything left running"

  validation {
    condition     = contains(["gp2", "gp3", "io1", "io2", "sc1", "st1"], var.ebs_volume_type)
    error_message = "ebs_volume_type must be an EBS volume type the CSI driver accepts: gp2, gp3, io1, io2, sc1 or st1."
  }
}

variable "ebs_iops_per_gb" {
  type        = number
  default     = 50
  description = "IOPS per provisioned GiB, as the _monolithic template set it. Only meaningful for io1 and io2"

  validation {
    condition     = var.ebs_iops_per_gb > 0
    error_message = "ebs_iops_per_gb must be greater than zero."
  }
}

variable "ebs_fstype" {
  type        = string
  default     = "xfs"
  description = "File system the driver formats the volume with, as the _monolithic template set it"

  validation {
    condition     = contains(["ext2", "ext3", "ext4", "xfs"], var.ebs_fstype)
    error_message = "ebs_fstype must be one of ext2, ext3, ext4 or xfs."
  }
}

variable "ebs_volume_size" {
  type        = string
  default     = "4Gi"
  description = "Size of the EBS claim, as the _monolithic template set it"

  validation {
    condition     = can(regex("^[0-9]+(Gi|Ti)$", var.ebs_volume_size))
    error_message = "ebs_volume_size must be a Kubernetes storage quantity in Gi or Ti (e.g. 4Gi)."
  }
}

variable "ebs_allowed_zones" {
  type        = list(string)
  default     = []
  description = "Zones the class may place a volume in, as full zone names. An EBS volume exists in one zone and can only be attached by a node in that zone, so restricting this to the zones the node group spans keeps a claim from binding somewhere the pod cannot follow"

  validation {
    condition     = alltrue([for z in var.ebs_allowed_zones : can(regex("^[a-z]{2}(-[a-z]+)+-[0-9][a-z]$", z))])
    error_message = "ebs_allowed_zones must contain full availability zone names (e.g. ap-northeast-2a)."
  }

  validation {
    condition     = var.create_ebs_workload == false || length(var.ebs_allowed_zones) > 0
    error_message = "ebs_allowed_zones must name at least one zone when create_ebs_workload is true; an empty allowedTopologies matchLabelExpressions is rejected by the API."
  }
}

# --- S3 ---

variable "create_s3_workload" {
  type        = bool
  default     = true
  description = "Whether to create the Mountpoint volume, claim and Deployment. False on a Fargate-only cluster, where the driver's addon cannot run"
}

variable "s3_bucket_name" {
  type        = string
  default     = null
  description = "Bucket the Mountpoint volume exposes. Required when create_s3_workload is true"

  validation {
    condition     = var.s3_bucket_name == null || can(regex("^[a-z0-9]([a-z0-9.-]*[a-z0-9])?$", var.s3_bucket_name))
    error_message = "s3_bucket_name must be a valid S3 bucket name, or null."
  }

  validation {
    condition     = var.create_s3_workload == false || var.s3_bucket_name != null
    error_message = "s3_bucket_name is required when create_s3_workload is true, because the PersistentVolume names the bucket in its volumeAttributes."
  }
}

variable "s3_allow_delete" {
  type        = bool
  default     = true
  description = "Whether the Mountpoint volume is mounted with allow-delete. Without it the mount is effectively append-only and `rm` inside the directory fails, which reads like a permissions problem"
}

variable "s3_nominal_capacity" {
  type        = string
  default     = "20Gi"
  description = "Capacity declared on the Mountpoint volume and its claim, as the _monolithic template set it. Required by the API and ignored by the driver, since a bucket has no size - but the two have to agree or the claim will not bind"

  validation {
    condition     = can(regex("^[0-9]+(Gi|Ti)$", var.s3_nominal_capacity))
    error_message = "s3_nominal_capacity must be a Kubernetes storage quantity in Gi or Ti (e.g. 20Gi)."
  }
}

# --- Objects with no volume ---

variable "create_plain_workloads" {
  type        = bool
  default     = true
  description = "Whether to create the bare Pod and the node-selected Deployment. The Pod is the one object type the project's own notes flag as restoring unreliably, which is worth being able to look at"
}

variable "app_replicas" {
  type        = number
  default     = 4
  description = "Replicas of the node-selected Deployment, as the _monolithic template set them"

  validation {
    condition     = var.app_replicas >= 1
    error_message = "app_replicas must be at least 1."
  }
}

variable "app_node_selector" {
  type        = map(string)
  default     = {}
  description = "nodeSelector on that Deployment, or empty for none. The _monolithic template pinned it to the node group's label; on a Fargate-only cluster there is no node to carry one, so the selector is left out rather than making the pods unschedulable (rules.md B-4)"
}

# --- RBAC ---

variable "create_rbac_objects" {
  type        = bool
  default     = true
  description = "Whether to create the ServiceAccount, Role, RoleBinding, ClusterRole and ClusterRoleBinding. The project's notes list all five as restorable - the cluster-scoped pair only when the restore role holds AmazonEKSClusterAdminPolicy - and the _monolithic template created none of them, so that claim was untested"
}

variable "rbac_name" {
  type        = string
  default     = "backup-demo"
  description = "Name shared by the five RBAC objects. One name, so the bindings cannot end up pointing at something that was renamed (rules.md B-5)"

  validation {
    condition     = can(regex("^[a-z0-9]([-a-z0-9]*[a-z0-9])?$", var.rbac_name))
    error_message = "rbac_name must be a valid lowercase RFC 1123 label."
  }
}

variable "driver_dependency" {
  type        = any
  default     = null
  description = "Value the caller passes purely to order this module after the CSI driver addons, the file system's mount targets and the capacity these objects need (rules.md D-4)"
}

variable "app_tolerations" {
  type = list(object({
    key      = string
    operator = string
    value    = string
    effect   = string
  }))
  default     = []
  description = "Tolerations on the node-selected Deployment, in Kubernetes form. Needed whenever app_node_selector points at a tainted node group: the selector alone places the pod there and the taint keeps it out, which shows up as Pending with a selector that reads correctly. Empty by default, for a node group with no taints"

  validation {
    condition     = alltrue([for t in var.app_tolerations : contains(["Exists", "Equal"], t.operator)])
    error_message = "each toleration operator must be Exists or Equal."
  }

  validation {
    condition     = alltrue([for t in var.app_tolerations : contains(["NoSchedule", "PreferNoSchedule", "NoExecute"], t.effect)])
    error_message = "each toleration effect must be NoSchedule, PreferNoSchedule or NoExecute - the Kubernetes spelling, not the EKS API's NO_SCHEDULE."
  }
}
