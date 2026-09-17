variable "aws_region" {
  type        = string
  default     = null
  description = "Target AWS region. When null, falls back to the provider default chain (AWS_REGION, profile, etc.)"
}
variable "prefix" {
  type        = string
  default     = "eks"
  description = "Prefix for the network resources' Name tags (\"eks\" produces eks-vpc, eks-igw, eks-public-a, ...)"

  validation {
    condition     = can(regex("^[a-z0-9][a-z0-9-]*$", var.prefix))
    error_message = "prefix must be lowercase alphanumeric, optionally with hyphens."
  }
}
variable "vpc_cidr_block" {
  type        = string
  default     = "10.0.0.0/16"
  description = "CIDR block for the VPC"

  validation {
    condition     = can(cidrhost(var.vpc_cidr_block, 0))
    error_message = "vpc_cidr_block must be a valid IPv4 CIDR block (e.g. 10.0.0.0/16)."
  }
}
variable "cluster_name" {
  type        = string
  default     = "eks-cluster"
  description = "Name of the EKS cluster"

  validation {
    condition     = can(regex("^[0-9A-Za-z][A-Za-z0-9\\-_]{0,99}$", var.cluster_name))
    error_message = "cluster_name must start with a letter or digit and contain only letters, digits, hyphens and underscores (100 characters or fewer)."
  }
}
variable "kubernetes_version" {
  type        = string
  default     = "1.33"
  description = "EKS cluster Kubernetes version (1.XX)"

  validation {
    condition     = contains(["1.31", "1.32", "1.33"], var.kubernetes_version)
    error_message = "kubernetes_version must be one of: 1.31, 1.32, 1.33."
  }
}
variable "endpoint_public_access" {
  type        = bool
  default     = true
  description = "Whether the EKS cluster API server endpoint is reachable from the public internet. Needed because the kubectl provider runs from the machine executing terraform apply rather than from inside the VPC (rules.md E-2). Restrict access with public_access_cidrs rather than leaving it open to 0.0.0.0/0"
}
variable "public_access_cidrs" {
  type        = list(string)
  default     = ["0.0.0.0/0"]
  description = "CIDR blocks allowed to reach the EKS API server's public endpoint when endpoint_public_access is true. Set this to your own address in CIDR form (e.g. [\"203.0.113.4/32\"]) instead of leaving the default: bootstrap_cluster_creator_admin_permissions grants anyone who can reach this endpoint with the creating AWS identity full cluster admin"

  validation {
    condition     = alltrue([for cidr in var.public_access_cidrs : can(cidrhost(cidr, 0))])
    error_message = "public_access_cidrs must contain valid IPv4 CIDR blocks."
  }
}
variable "key_name" {
  type        = string
  default     = "eks-key"
  description = "Name of the EC2 key pair created for the VS Code instance and the managed node group"

  validation {
    condition     = can(regex("^[ -~]{1,255}$", var.key_name))
    error_message = "key_name must be a non-empty string of printable ASCII characters, 255 characters or fewer."
  }
}
variable "node_group_name" {
  type        = string
  default     = "nodegroup"
  description = "Name of the managed node group hosting the driver and the demo pod"

  validation {
    condition     = length(var.node_group_name) > 0
    error_message = "node_group_name must not be empty."
  }
}
variable "node_group_instance_types" {
  type        = list(string)
  default     = ["t3.medium"]
  description = "EC2 instance types for the managed node group"

  validation {
    condition     = length(var.node_group_instance_types) > 0
    error_message = "node_group_instance_types must contain at least one instance type."
  }
}
variable "node_group_desired_size" {
  type        = number
  default     = 2
  description = "Desired node count for the managed node group"

  validation {
    condition     = var.node_group_desired_size >= 0
    error_message = "node_group_desired_size must be zero or greater."
  }
}
variable "node_group_min_size" {
  type        = number
  default     = 2
  description = "Minimum node count for the managed node group"

  validation {
    condition     = var.node_group_min_size >= 0
    error_message = "node_group_min_size must be zero or greater."
  }
}
variable "node_group_max_size" {
  type        = number
  default     = 2
  description = "Maximum node count for the managed node group"

  validation {
    condition     = var.node_group_max_size >= 0
    error_message = "node_group_max_size must be zero or greater."
  }
}
variable "bucket_prefix" {
  type        = string
  default     = "eks-mountpoint-s3-"
  description = "Prefix AWS appends a unique suffix to when naming the bucket the driver mounts. A prefix rather than a fixed name because bucket names are globally unique"

  validation {
    condition     = can(regex("^[a-z0-9][a-z0-9.-]{1,36}$", var.bucket_prefix))
    error_message = "bucket_prefix must be 2-37 characters of lowercase letters, digits, dots or hyphens and start with a letter or digit."
  }
}
variable "bucket_force_destroy" {
  type        = bool
  default     = true
  description = "Whether terraform destroy may delete the bucket while it still holds the objects the demo pod wrote. Without it, destroy stops on a bucket S3 refuses to remove"
}
variable "mountpoint_s3_csi_driver_addon_version" {
  type        = string
  default     = null
  description = "Specific aws-mountpoint-s3-csi-driver addon version (e.g. v2.1.0-eksbuild.1). When null, EKS picks the default version for the cluster's Kubernetes version"

  validation {
    condition     = var.mountpoint_s3_csi_driver_addon_version == null || can(regex("^v[0-9]+\\.[0-9]+\\.[0-9]+-eksbuild\\.[0-9]+$", var.mountpoint_s3_csi_driver_addon_version))
    error_message = "mountpoint_s3_csi_driver_addon_version must look like v2.1.0-eksbuild.1, or null."
  }
}
variable "allow_delete" {
  type        = bool
  default     = true
  description = "Whether the pod may delete files in the bucket. Drives both the driver's s3:DeleteObject permission and Mountpoint's allow-delete mount option, which have to agree: the policy alone does not enable deletion, and the mount option alone fails with AccessDenied (rules.md B-5)"
}
variable "mount_prefix" {
  type        = string
  default     = "pod/"
  description = "Key prefix within the bucket the volume is rooted at, so the pod sees only this part of it. Must end with a slash. Set to null to mount the whole bucket"

  validation {
    condition     = var.mount_prefix == null || can(regex("/$", var.mount_prefix))
    error_message = "mount_prefix must end with a slash (e.g. pod/), or be null to mount the whole bucket."
  }
}
variable "volume_capacity" {
  type        = string
  default     = "20Gi"
  description = "Capacity declared on the PersistentVolume and requested by the claim. S3 has no size limit, so the driver ignores this figure and it exists only because the Kubernetes API requires it"

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
variable "vscode_instance_type" {
  type        = string
  default     = "t3.medium"
  description = "EC2 instance type for the VS Code EC2 instance"

  validation {
    condition     = can(regex("^[a-z0-9]+\\.[a-z0-9]+$", var.vscode_instance_type))
    error_message = "vscode_instance_type must be a valid EC2 instance type (e.g. t3.medium)."
  }
}
variable "allow_inbound_from_anywhere" {
  type        = bool
  default     = true
  description = "Whether to allow inbound access to the code-server port (8000) on the VS Code instance from 0.0.0.0/0. Set false and reach code-server through SSM Session Manager port forwarding instead"
}
variable "kubectl_download_version" {
  type        = string
  default     = "1.33.3/2025-08-03"
  description = "Version and release-date path segment of the kubectl binary downloaded onto the VS Code EC2 instance, from the amazon-eks S3 bucket layout (<version>/<date>). Keep it within one minor version of kubernetes_version to stay inside the supported skew"

  validation {
    condition     = can(regex("^[0-9]+\\.[0-9]+\\.[0-9]+/[0-9]{4}-[0-9]{2}-[0-9]{2}$", var.kubectl_download_version))
    error_message = "kubectl_download_version must look like 1.33.3/2025-08-03."
  }
}
variable "marker_file_path" {
  type        = string
  default     = "/run/terraform"
  description = "Directory holding the bootstrap marker files, shared between the vscode_ec2 module (which touches <path>/userdata as the last step of its user data) and the SSM association that polls for it before writing the README (rules.md D-5/H-2). Under /run so the markers vanish on reboot rather than making a stale file look like a completed bootstrap"

  validation {
    condition     = can(regex("^/", var.marker_file_path))
    error_message = "marker_file_path must be an absolute path starting with '/'."
  }
}
variable "readme_timeout_seconds" {
  type        = number
  default     = 900
  description = "How long the SSM association waits for the README command to report success. It has to cover the whole instance bootstrap, since the command's first act is to wait for the user data marker file"

  validation {
    condition     = var.readme_timeout_seconds > 0
    error_message = "readme_timeout_seconds must be greater than zero."
  }
}
