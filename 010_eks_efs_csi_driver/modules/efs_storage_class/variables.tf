variable "storage_class_name" {
  type        = string
  default     = "efs-sc"
  description = "Name of the StorageClass backed by the EFS CSI driver"
  validation {
    condition     = can(regex("^[a-z0-9]([-a-z0-9]*[a-z0-9])?$", var.storage_class_name))
    error_message = "storage_class_name must be a valid lowercase RFC 1123 DNS label."
  }
}
variable "provisioner" {
  type        = string
  default     = "efs.csi.aws.com"
  description = "CSI driver name that provisions volumes for this StorageClass. Pass the eks_efs_csi_driver_addon module's provisioner output rather than repeating the literal (rules.md B-5)"
  validation {
    condition     = length(var.provisioner) > 0
    error_message = "provisioner must not be empty."
  }
}
variable "file_system_id" {
  type        = string
  description = "ID of the EFS file system volumes are provisioned in. Pass the efs_file_system module's file_system_id output, which is what the _monolithic design left as a FILE_SYSTEM_ID placeholder for the operator to paste in by hand"
  validation {
    condition     = can(regex("^fs-[0-9a-f]+$", var.file_system_id))
    error_message = "file_system_id must be a valid EFS file system ID (e.g. fs-0123456789abcdef0)."
  }
}
variable "provisioning_mode" {
  type        = string
  default     = "efs-ap"
  description = "How the driver provisions storage. efs-ap creates one EFS access point per claim, which is the only dynamic provisioning mode the driver supports"
  validation {
    condition     = contains(["efs-ap"], var.provisioning_mode)
    error_message = "provisioning_mode must be efs-ap, the only dynamic provisioning mode the EFS CSI driver supports."
  }
}
variable "directory_perms" {
  type        = string
  default     = "700"
  description = "POSIX permissions the driver sets on each access point's root directory"
  validation {
    condition     = can(regex("^[0-7]{3,4}$", var.directory_perms))
    error_message = "directory_perms must be an octal permission string (e.g. 700)."
  }
}
variable "base_path" {
  type        = string
  default     = null
  description = "Optional path within the file system under which access point root directories are created. When null the parameter is omitted and the driver uses the file system root"
  validation {
    condition     = var.base_path == null || can(regex("^/", var.base_path))
    error_message = "base_path must be an absolute path starting with '/', or null."
  }
}
variable "reclaim_policy" {
  type        = string
  default     = "Delete"
  description = "What happens to the access point backing a claim when the claim is deleted. Delete removes the access point (and the data under its root directory), Retain leaves both in place"
  validation {
    condition     = contains(["Delete", "Retain"], var.reclaim_policy)
    error_message = "reclaim_policy must be either Delete or Retain."
  }
}
variable "set_as_default_storage_class" {
  type        = bool
  default     = false
  description = "Whether to mark this StorageClass as the cluster default, so claims that omit storageClassName use it"
}
variable "namespace" {
  type        = string
  default     = "default"
  description = "Namespace the demo PersistentVolumeClaim and Deployment are created in. StorageClass itself is cluster scoped"
  validation {
    condition     = length(var.namespace) > 0
    error_message = "namespace must not be empty."
  }
}
variable "create_demo_workload" {
  type        = bool
  default     = true
  description = "Whether to create the demo Deployment and PersistentVolumeClaim. Its replicas all append timestamps to the same file on the shared volume, which is what demonstrates ReadWriteMany - the thing EFS offers and EBS does not"
}
variable "demo_deployment_name" {
  type        = string
  default     = "efs"
  description = "Name of the demo Deployment created when create_demo_workload is true"
  validation {
    condition     = can(regex("^[a-z0-9]([-a-z0-9]*[a-z0-9])?$", var.demo_deployment_name))
    error_message = "demo_deployment_name must be a valid lowercase RFC 1123 DNS label."
  }
}
variable "demo_claim_name" {
  type        = string
  default     = "efs-claim"
  description = "Name of the demo PersistentVolumeClaim created when create_demo_workload is true"
  validation {
    condition     = can(regex("^[a-z0-9]([-a-z0-9]*[a-z0-9])?$", var.demo_claim_name))
    error_message = "demo_claim_name must be a valid lowercase RFC 1123 DNS label."
  }
}
variable "demo_image" {
  type        = string
  default     = "public.ecr.aws/amazonlinux/amazonlinux"
  description = "Container image used by the demo Deployment. Pulled from ECR Public rather than the _monolithic design's rockylinux:8 on Docker Hub, whose anonymous pull rate limits make a multi-replica Deployment flaky"
  validation {
    condition     = length(var.demo_image) > 0
    error_message = "demo_image must not be empty."
  }
}
variable "demo_replica_count" {
  type        = number
  default     = 3
  description = "Replica count for the demo Deployment. More than one is the point: with ReadWriteMany every replica mounts the same volume, so they can be spread across nodes and availability zones and still write to one file"
  validation {
    condition     = var.demo_replica_count > 0
    error_message = "demo_replica_count must be greater than zero."
  }
}
variable "demo_volume_size" {
  type        = string
  default     = "5Gi"
  description = "Storage requested by the demo PersistentVolumeClaim. EFS is elastic and enforces no quota per access point, so this figure only satisfies the Kubernetes API's requirement that a claim ask for something"
  validation {
    condition     = can(regex("^[0-9]+(Ei|Pi|Ti|Gi|Mi|Ki)$", var.demo_volume_size))
    error_message = "demo_volume_size must be a Kubernetes binary quantity (e.g. 5Gi)."
  }
}
