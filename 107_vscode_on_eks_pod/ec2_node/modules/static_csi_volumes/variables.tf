variable "namespace" {
  type        = string
  default     = "default"
  description = "Namespace the claims are created in. A PersistentVolume is cluster scoped, so only the claim has one"

  validation {
    condition     = can(regex("^[a-z0-9]([-a-z0-9]*[a-z0-9])?$", var.namespace))
    error_message = "namespace must be a valid lowercase RFC 1123 label."
  }
}

variable "efs_volumes" {
  type = map(object({
    file_system_id  = string
    access_point_id = optional(string)
  }))
  default     = {}
  description = <<-DESC
    EFS volumes to expose, keyed by the name both the PersistentVolume and its claim take.

    A map with caller-chosen keys rather than a list, because the file system id is another module's
    output and unknown at plan time - for_each needs its keys known then, and a set built from the values
    would put an unknown value in the key position (rules.md B-8).
  DESC

  validation {
    condition     = alltrue([for k in keys(var.efs_volumes) : can(regex("^[a-z0-9]([-a-z0-9]*[a-z0-9])?$", k))])
    error_message = "efs_volumes keys become Kubernetes object names, so each must be a valid lowercase RFC 1123 label."
  }

  validation {
    condition     = alltrue([for v in values(var.efs_volumes) : can(regex("^fs-[0-9a-f]+$", v.file_system_id))])
    error_message = "efs_volumes file_system_id must be an EFS file system id (e.g. fs-0123456789abcdef0)."
  }

  validation {
    condition     = alltrue([for v in values(var.efs_volumes) : v.access_point_id == null || can(regex("^fsap-[0-9a-f]+$", v.access_point_id))])
    error_message = "efs_volumes access_point_id must be an EFS access point id (e.g. fsap-0123456789abcdef0), or null to mount the file system root."
  }
}

variable "s3_volumes" {
  type = map(object({
    bucket_name         = string
    region              = string
    allow_delete        = optional(bool, true)
    extra_mount_options = optional(list(string), [])
  }))
  default     = {}
  description = "Buckets to expose through Mountpoint for S3, keyed by the name both the PersistentVolume and its claim take. A map for the same reason as efs_volumes (rules.md B-8)"

  validation {
    condition     = alltrue([for k in keys(var.s3_volumes) : can(regex("^[a-z0-9]([-a-z0-9]*[a-z0-9])?$", k))])
    error_message = "s3_volumes keys become Kubernetes object names, so each must be a valid lowercase RFC 1123 label."
  }

  validation {
    condition     = alltrue([for v in values(var.s3_volumes) : can(regex("^[a-z0-9]([a-z0-9.-]*[a-z0-9])?$", v.bucket_name))])
    error_message = "s3_volumes bucket_name must be a valid S3 bucket name."
  }

  validation {
    condition     = alltrue([for v in values(var.s3_volumes) : can(regex("^[a-z]{2}(-[a-z]+)+-[0-9]$", v.region))])
    error_message = "s3_volumes region must be a valid AWS region name; Mountpoint needs it as a mount option because the bucket is addressed regionally."
  }
}

variable "mount_uid" {
  type        = number
  default     = 1000
  description = "uid the Mountpoint volumes appear to be owned by. 1000 is the coder user in the code-server image; the driver mounts as root otherwise and the container gets permission denied on a directory it can see"

  validation {
    condition     = var.mount_uid >= 0
    error_message = "mount_uid must not be negative."
  }
}

variable "mount_gid" {
  type        = number
  default     = 1000
  description = "gid the Mountpoint volumes appear to be owned by"

  validation {
    condition     = var.mount_gid >= 0
    error_message = "mount_gid must not be negative."
  }
}

variable "driver_dependency" {
  type        = any
  default     = null
  description = "Value the caller passes purely to order this module after the CSI driver addons and the mount targets these volumes need (rules.md D-4)"
}
