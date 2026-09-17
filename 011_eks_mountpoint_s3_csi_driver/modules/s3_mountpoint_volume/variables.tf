variable "persistent_volume_name" {
  type        = string
  default     = "s3-pv"
  description = "Name of the statically provisioned PersistentVolume backed by the bucket"
  validation {
    condition     = can(regex("^[a-z0-9]([-a-z0-9]*[a-z0-9])?$", var.persistent_volume_name))
    error_message = "persistent_volume_name must be a valid lowercase RFC 1123 DNS label."
  }
}
variable "claim_name" {
  type        = string
  default     = "s3-pvc"
  description = "Name of the PersistentVolumeClaim bound to that volume"
  validation {
    condition     = can(regex("^[a-z0-9]([-a-z0-9]*[a-z0-9])?$", var.claim_name))
    error_message = "claim_name must be a valid lowercase RFC 1123 DNS label."
  }
}
variable "namespace" {
  type        = string
  default     = "default"
  description = "Namespace the claim and the demo pod live in. The PersistentVolume itself is cluster scoped, but its claimRef names this namespace so no claim in another namespace can take the volume"
  validation {
    condition     = can(regex("^[a-z0-9]([-a-z0-9]*[a-z0-9])?$", var.namespace))
    error_message = "namespace must be a valid lowercase RFC 1123 DNS label."
  }
}
variable "driver" {
  type        = string
  default     = "s3.csi.aws.com"
  description = "CSI driver backing the volume. Pass the eks_mountpoint_s3_csi_driver_addon module's driver output rather than repeating the literal (rules.md B-5)"
  validation {
    condition     = length(var.driver) > 0
    error_message = "driver must not be empty."
  }
}
variable "bucket_name" {
  type        = string
  description = "Name of the bucket mounted into the pod, passed as the volume's bucketName attribute. Pass the s3_bucket module's bucket_name output"
  validation {
    condition     = can(regex("^[a-z0-9][a-z0-9.-]{1,61}[a-z0-9]$", var.bucket_name))
    error_message = "bucket_name must be a valid S3 bucket name (3-63 lowercase characters)."
  }
}
variable "volume_handle" {
  type        = string
  default     = "s3-csi-driver-volume"
  description = "Opaque volume handle the driver identifies this volume by. Must be unique per PersistentVolume within the cluster - two volumes sharing a handle silently mount the same thing"
  validation {
    condition     = length(var.volume_handle) > 0
    error_message = "volume_handle must not be empty."
  }
}
variable "region" {
  type        = string
  description = "Region of the bucket, passed as Mountpoint's region mount option. Required because the driver's pods can run in a different region than the bucket, and Mountpoint does not discover it"
  validation {
    condition     = can(regex("^[a-z]{2}-[a-z]+-[0-9]$", var.region))
    error_message = "region must be an AWS region name (e.g. ap-northeast-2)."
  }
}
variable "allow_delete" {
  type        = bool
  default     = true
  description = "Whether to add Mountpoint's allow-delete mount option, which is what lets a pod unlink files. The driver's IAM policy must also grant s3:DeleteObject: pass the addon module's allow_delete output so the two are driven by one switch rather than set independently (rules.md B-5)"
}
variable "prefix" {
  type        = string
  default     = "pod/"
  description = "Key prefix within the bucket the volume is rooted at, so the pod sees only this part of the bucket. Must end with a slash - Mountpoint treats it as a directory. When null the whole bucket is mounted"
  validation {
    condition     = var.prefix == null || can(regex("/$", var.prefix))
    error_message = "prefix must end with a slash (e.g. pod/), or be null to mount the whole bucket."
  }
}
variable "extra_mount_options" {
  type        = list(string)
  default     = []
  description = "Additional Mountpoint mount options (e.g. uid=1000, gid=1000, allow-other), appended after the ones this module derives. Values come from configuration, so a plain list is fine here (rules.md B-8)"
  validation {
    condition     = alltrue([for option in var.extra_mount_options : length(option) > 0])
    error_message = "extra_mount_options must not contain empty strings."
  }
}
variable "volume_capacity" {
  type        = string
  default     = "20Gi"
  description = "Capacity declared on the PersistentVolume and requested by the claim. S3 has no size limit, so this figure is ignored by the driver and exists only because the Kubernetes API requires it"
  validation {
    condition     = can(regex("^[0-9]+(Ei|Pi|Ti|Gi|Mi|Ki)$", var.volume_capacity))
    error_message = "volume_capacity must be a Kubernetes binary quantity (e.g. 20Gi)."
  }
}
variable "create_demo_pod" {
  type        = bool
  default     = true
  description = "Whether to create the demo pod that writes a timestamped file into the mounted bucket, verifying the mount end to end"
}
variable "demo_pod_name" {
  type        = string
  default     = "s3-app"
  description = "Name of the demo pod created when create_demo_pod is true"
  validation {
    condition     = can(regex("^[a-z0-9]([-a-z0-9]*[a-z0-9])?$", var.demo_pod_name))
    error_message = "demo_pod_name must be a valid lowercase RFC 1123 DNS label."
  }
}
variable "demo_image" {
  type        = string
  default     = "public.ecr.aws/amazonlinux/amazonlinux"
  description = "Container image used by the demo pod. Pulled from ECR Public rather than the _monolithic template's ubuntu on Docker Hub, whose anonymous pull rate limits make the pod flaky"
  validation {
    condition     = length(var.demo_image) > 0
    error_message = "demo_image must not be empty."
  }
}
variable "demo_mount_path" {
  type        = string
  default     = "/data"
  description = "Path the bucket is mounted at inside the demo pod"
  validation {
    condition     = can(regex("^/", var.demo_mount_path))
    error_message = "demo_mount_path must be an absolute path starting with '/'."
  }
}
