variable "storage_class_name" {
  type        = string
  default     = "ebs-sc"
  description = "Name of the StorageClass backed by the EBS CSI driver"

  validation {
    condition     = can(regex("^[a-z0-9]([-a-z0-9]*[a-z0-9])?$", var.storage_class_name))
    error_message = "storage_class_name must be a valid lowercase RFC 1123 DNS label."
  }
}
variable "provisioner" {
  type        = string
  default     = "ebs.csi.aws.com"
  description = "CSI driver name that provisions volumes for this StorageClass. Pass the eks_ebs_csi_driver_addon module's provisioner output rather than repeating the literal (rules.md B-5)"

  validation {
    condition     = length(var.provisioner) > 0
    error_message = "provisioner must not be empty."
  }
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
variable "volume_type" {
  type        = string
  default     = "io1"
  description = "EBS volume type provisioned for claims using this StorageClass"

  validation {
    condition     = contains(["gp2", "gp3", "io1", "io2", "sc1", "st1", "standard"], var.volume_type)
    error_message = "volume_type must be one of: gp2, gp3, io1, io2, sc1, st1, standard."
  }
}
variable "iops_per_gb" {
  type        = number
  default     = 50
  description = "Provisioned IOPS per requested GiB. Only rendered for the io1/io2 volume types, which are the only ones accepting iopsPerGB"

  validation {
    condition     = var.iops_per_gb > 0
    error_message = "iops_per_gb must be greater than zero."
  }
}
variable "fs_type" {
  type        = string
  default     = "xfs"
  description = "Filesystem the driver formats new volumes with"

  validation {
    condition     = contains(["ext2", "ext3", "ext4", "xfs", "ntfs"], var.fs_type)
    error_message = "fs_type must be one of: ext2, ext3, ext4, xfs, ntfs."
  }
}
variable "encrypted" {
  type        = bool
  default     = true
  description = "Whether volumes provisioned through this StorageClass are encrypted at rest"
}
variable "volume_binding_mode" {
  type        = string
  default     = "WaitForFirstConsumer"
  description = "When the volume is provisioned. WaitForFirstConsumer delays creation until a pod is scheduled so the volume lands in the pod's AZ; Immediate risks provisioning in an AZ the pod cannot run in"

  validation {
    condition     = contains(["Immediate", "WaitForFirstConsumer"], var.volume_binding_mode)
    error_message = "volume_binding_mode must be either Immediate or WaitForFirstConsumer."
  }
}
variable "reclaim_policy" {
  type        = string
  default     = "Delete"
  description = "What happens to the underlying EBS volume when its PersistentVolumeClaim is deleted"

  validation {
    condition     = contains(["Delete", "Retain"], var.reclaim_policy)
    error_message = "reclaim_policy must be either Delete or Retain."
  }
}
variable "allow_volume_expansion" {
  type        = bool
  default     = true
  description = "Whether claims using this StorageClass can be grown by editing the claim's requested size"
}
variable "set_as_default_storage_class" {
  type        = bool
  default     = false
  description = "Whether to mark this StorageClass as the cluster default, so claims that omit storageClassName use it"
}
variable "allowed_topology_zones" {
  type        = list(string)
  default     = []
  description = "Availability zones volumes may be provisioned in (e.g. the network module's availability_zones output). When empty, allowedTopologies is omitted and any zone in the cluster is eligible"

  validation {
    condition     = alltrue([for z in var.allowed_topology_zones : can(regex("^[a-z]{2}-[a-z]+-[0-9][a-z]$", z))])
    error_message = "allowed_topology_zones must contain availability zone names (e.g. ap-northeast-2a)."
  }
}
variable "create_demo_workload" {
  type        = bool
  default     = true
  description = "Whether to create the demo Deployment and PersistentVolumeClaim that append timestamps to a file on the mounted volume, verifying dynamic provisioning end to end"
}
variable "demo_deployment_name" {
  type        = string
  default     = "app-deployment"
  description = "Name of the demo Deployment created when create_demo_workload is true"

  validation {
    condition     = length(var.demo_deployment_name) > 0
    error_message = "demo_deployment_name must not be empty."
  }
}
variable "demo_claim_name" {
  type        = string
  default     = "ebs-claim"
  description = "Name of the demo PersistentVolumeClaim created when create_demo_workload is true"

  validation {
    condition     = length(var.demo_claim_name) > 0
    error_message = "demo_claim_name must not be empty."
  }
}
variable "demo_image" {
  type        = string
  default     = "public.ecr.aws/amazonlinux/amazonlinux"
  description = "Container image used by the demo Deployment"

  validation {
    condition     = length(var.demo_image) > 0
    error_message = "demo_image must not be empty."
  }
}
variable "demo_replica_count" {
  type        = number
  default     = 3
  description = "Replica count for the demo Deployment. All replicas share the single ReadWriteOnce claim, so they are scheduled onto the node the volume attaches to"

  validation {
    condition     = var.demo_replica_count > 0
    error_message = "demo_replica_count must be greater than zero."
  }
}
variable "demo_volume_size" {
  type        = string
  default     = "4Gi"
  description = "Storage requested by the demo PersistentVolumeClaim"

  validation {
    condition     = can(regex("^[0-9]+(Ei|Pi|Ti|Gi|Mi|Ki)$", var.demo_volume_size))
    error_message = "demo_volume_size must be a Kubernetes binary quantity (e.g. 4Gi)."
  }
}
