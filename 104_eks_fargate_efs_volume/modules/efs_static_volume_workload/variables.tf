variable "file_system_id" {
  type        = string
  description = "ID of the EFS file system both persistent volumes point at. This is the volumeHandle, and static provisioning means the file system must already exist"

  validation {
    condition     = can(regex("^fs-[0-9a-f]+$", var.file_system_id))
    error_message = "file_system_id must be a valid EFS file system ID (e.g. fs-0123456789abcdef0)."
  }
}

variable "namespace" {
  type        = string
  default     = "default"
  description = "Namespace the claims and pods are created in. It has to be one the Fargate profile selects, or the pods stay Pending with no node to land on"

  validation {
    condition     = can(regex("^[a-z0-9]([-a-z0-9]*[a-z0-9])?$", var.namespace))
    error_message = "namespace must be a valid lowercase RFC 1123 DNS label."
  }
}

variable "csi_driver_name" {
  type        = string
  default     = "efs.csi.aws.com"
  description = "Name of the CSI driver the volumes and the StorageClass reference. On Fargate this driver is part of the platform rather than something installed into the cluster"

  validation {
    condition     = length(var.csi_driver_name) > 0
    error_message = "csi_driver_name must not be empty."
  }
}

variable "register_csi_driver" {
  type        = bool
  default     = false
  description = "Whether to apply a CSIDriver object for csi_driver_name. False because Fargate registers it already and spec.attachRequired cannot be changed afterwards; the _monolithic template also wrote this manifest without applying it"
}

variable "storage_class_name" {
  type        = string
  default     = "efs-sc"
  description = "Name of the StorageClass the write volume and claim are matched through"

  validation {
    condition     = can(regex("^[a-z0-9]([-a-z0-9.]*[a-z0-9])?$", var.storage_class_name))
    error_message = "storage_class_name must be a valid lowercase RFC 1123 subdomain."
  }
}

variable "storage_capacity" {
  type        = string
  default     = "5Gi"
  description = "Capacity recorded on the volumes and requested by the claims. EFS grows on its own, so this is only the number the two sides have to agree on for the bind to happen"

  validation {
    condition     = can(regex("^[0-9]+(Ki|Mi|Gi|Ti|K|M|G|T)?$", var.storage_capacity))
    error_message = "storage_capacity must be a Kubernetes quantity such as 5Gi."
  }
}

variable "reclaim_policy" {
  type        = string
  default     = "Retain"
  description = "What happens to the volume when its claim goes away. Retain, so deleting the demo leaves the file system contents alone"

  validation {
    condition     = contains(["Retain", "Delete", "Recycle"], var.reclaim_policy)
    error_message = "reclaim_policy must be one of: Retain, Delete, Recycle."
  }
}

variable "write_volume_name" {
  type        = string
  default     = "efs-pv"
  description = "Name of the PersistentVolume bound through the StorageClass"

  validation {
    condition     = can(regex("^[a-z0-9]([-a-z0-9.]*[a-z0-9])?$", var.write_volume_name))
    error_message = "write_volume_name must be a valid lowercase RFC 1123 subdomain."
  }
}

variable "write_claim_name" {
  type        = string
  default     = "efs-pvc"
  description = "Name of the claim the writer pod mounts"

  validation {
    condition     = can(regex("^[a-z0-9]([-a-z0-9.]*[a-z0-9])?$", var.write_claim_name))
    error_message = "write_claim_name must be a valid lowercase RFC 1123 subdomain."
  }
}

variable "read_volume_name" {
  type        = string
  default     = "read-pv"
  description = "Name of the PersistentVolume bound directly by volumeName, with no StorageClass involved"

  validation {
    condition     = can(regex("^[a-z0-9]([-a-z0-9.]*[a-z0-9])?$", var.read_volume_name))
    error_message = "read_volume_name must be a valid lowercase RFC 1123 subdomain."
  }
}

variable "read_claim_name" {
  type        = string
  default     = "read-pvc"
  description = "Name of the claim the reader pod mounts"

  validation {
    condition     = can(regex("^[a-z0-9]([-a-z0-9.]*[a-z0-9])?$", var.read_claim_name))
    error_message = "read_claim_name must be a valid lowercase RFC 1123 subdomain."
  }
}

variable "write_pod_name" {
  type        = string
  default     = "write"
  description = "Name of the pod that appends timestamps to the shared file"

  validation {
    condition     = can(regex("^[a-z0-9]([-a-z0-9.]*[a-z0-9])?$", var.write_pod_name))
    error_message = "write_pod_name must be a valid lowercase RFC 1123 subdomain."
  }
}

variable "read_pod_name" {
  type        = string
  default     = "read"
  description = "Name of the pod that mounts the same file system read side"

  validation {
    condition     = can(regex("^[a-z0-9]([-a-z0-9.]*[a-z0-9])?$", var.read_pod_name))
    error_message = "read_pod_name must be a valid lowercase RFC 1123 subdomain."
  }
}

variable "image" {
  type        = string
  default     = "busybox"
  description = "Container image both pods run. Anything with a shell works; the pods only echo and sleep"

  validation {
    condition     = length(var.image) > 0
    error_message = "image must not be empty."
  }
}

variable "volume_mount_name" {
  type        = string
  default     = "efs-volume"
  description = "Name tying each pod's volumes entry to its volumeMounts entry. Pod-local, so both pods can use the same name"

  validation {
    condition     = can(regex("^[a-z0-9]([-a-z0-9]*[a-z0-9])?$", var.volume_mount_name))
    error_message = "volume_mount_name must be a valid lowercase RFC 1123 label."
  }
}

variable "mount_path" {
  type        = string
  default     = "/data"
  description = "Path inside both containers where the file system is mounted"

  validation {
    condition     = can(regex("^/", var.mount_path))
    error_message = "mount_path must be an absolute path starting with '/'."
  }
}

variable "output_file_name" {
  type        = string
  default     = "out1.txt"
  description = "File under mount_path the writer appends to and the reader reads. One name for both sides, so the verification command in outputs cannot drift from what the writer creates (rules.md B-5)"

  validation {
    condition     = can(regex("^[^/]+$", var.output_file_name))
    error_message = "output_file_name must be a file name, not a path."
  }
}

variable "write_interval_seconds" {
  type        = number
  default     = 30
  description = "Seconds the writer sleeps between appends"

  validation {
    condition     = var.write_interval_seconds > 0 && floor(var.write_interval_seconds) == var.write_interval_seconds
    error_message = "write_interval_seconds must be a positive whole number of seconds."
  }
}
