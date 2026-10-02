variable "aws_region" {
  type        = string
  default     = null
  description = "Target AWS region. When null, falls back to the provider default chain (AWS_REGION, profile, etc.)"

  validation {
    condition     = var.aws_region == null || can(regex("^[a-z]{2}(-gov)?-[a-z]+-[0-9]$", var.aws_region))
    error_message = "aws_region must be a valid AWS region such as ap-northeast-2, or null to fall back to the provider default chain."
  }
}
variable "cluster_name" {
  type        = string
  default     = "multi-volume-cluster"
  description = "Name of the EKS cluster"

  validation {
    condition     = can(regex("^[a-zA-Z0-9][a-zA-Z0-9-_]{0,99}$", var.cluster_name))
    error_message = "cluster_name must start with a letter or digit and contain only letters, digits, hyphens and underscores (100 characters or fewer)."
  }
}
variable "kubernetes_version" {
  type        = string
  default     = "1.33"
  description = "Kubernetes version for the EKS cluster"

  validation {
    condition     = can(regex("^1\\.(3[0-9]|[4-9][0-9])$", var.kubernetes_version))
    error_message = "kubernetes_version must be a supported 1.XX version, e.g. 1.33."
  }
}
variable "kubectl_download_version" {
  type        = string
  default     = "1.33.3/2025-08-03"
  description = "Version path used to download kubectl onto the VS Code instance, in <version>/<release-date> form. Raised together with kubernetes_version: kubectl more than one minor version from the API server is outside the supported skew (rules.md H-1)"

  validation {
    condition     = can(regex("^[0-9]+\\.[0-9]+\\.[0-9]+/[0-9]{4}-[0-9]{2}-[0-9]{2}$", var.kubectl_download_version))
    error_message = "kubectl_download_version must look like 1.33.3/2025-08-03."
  }
}
variable "endpoint_public_access" {
  type        = bool
  default     = true
  description = "Whether the EKS API server endpoint is reachable from the internet. True so kubectl can inspect the nodes, which is the only way to see what this project did. Deliberately not pinned with a validation, unlike the other EKS projects in this repository: nothing here is applied through a Kubernetes provider, so setting it false costs only convenience rather than breaking the apply (rules.md B-1/E-9). Narrow public_access_cidrs rather than leaving the default open"
}
variable "public_access_cidrs" {
  type        = list(string)
  default     = ["0.0.0.0/0"]
  description = "CIDR blocks allowed to reach the public API server endpoint. Set this to your own address in CIDR form: bootstrap_cluster_creator_admin_permissions means anyone who can reach this endpoint with a valid AWS credential for the creating principal has cluster-admin"

  validation {
    condition     = alltrue([for cidr in var.public_access_cidrs : can(cidrhost(cidr, 0))])
    error_message = "public_access_cidrs must contain valid IPv4 CIDR blocks."
  }
}
variable "key_name" {
  type        = string
  default     = "multi-volume-key"
  description = "Name of the EC2 key pair created for the demo instance and attached to the worker nodes' launch template"

  validation {
    condition     = length(var.key_name) > 0
    error_message = "key_name must not be empty."
  }
}
variable "node_group_instance_types" {
  type        = list(string)
  default     = ["t3.medium"]
  description = "Instance types for the managed node group. Every type here is Nitro-based, which is what makes the device naming caveat below apply: EBS volumes appear as /dev/nvme<N>n1 rather than at the name given in the block device mapping"

  validation {
    condition     = length(var.node_group_instance_types) > 0
    error_message = "node_group_instance_types must contain at least one instance type."
  }
}
variable "node_group_desired_size" {
  type        = number
  default     = 2
  description = "Desired node count, two as the _monolithic template had it"

  validation {
    condition     = var.node_group_desired_size >= 1
    error_message = "node_group_desired_size must be at least 1."
  }
}
variable "node_group_min_size" {
  type        = number
  default     = 2
  description = "Minimum node count"

  validation {
    condition     = var.node_group_min_size >= 1
    error_message = "node_group_min_size must be at least 1."
  }
}
variable "node_group_max_size" {
  type        = number
  default     = 4
  description = "Maximum node count, four as the _monolithic template had it. Nothing scales the node group here, so this is only headroom for a manual resize"

  validation {
    condition     = var.node_group_max_size >= var.node_group_min_size
    error_message = "node_group_max_size must be greater than or equal to node_group_min_size."
  }
}
variable "container_volume_device_name" {
  type        = string
  default     = "/dev/sdz"
  description = "Block device mapping name for the volume that holds the container runtime's state. One value feeds two places that must agree: the launch template's mapping, and the script that formats and mounts it (rules.md B-5). On a Nitro instance this is not the path the kernel uses - the volume shows up as /dev/nvme<N>n1 in attach order - but amazon-ec2-utils, which the EKS-optimized AMIs carry, ships udev rules that recreate a symlink here. Addressing the symlink is why the script does not have to guess an nvme index, which is what the _monolithic template did"

  validation {
    condition     = can(regex("^/dev/(sd[b-z]|xvd[b-z])$", var.container_volume_device_name))
    error_message = "container_volume_device_name must be /dev/sd[b-z] or /dev/xvd[b-z]; /dev/sda and /dev/xvda are reserved for the root volume."
  }
}
variable "container_volume_size" {
  type        = number
  default     = 80
  description = "Size in GiB of the container runtime volume, 80 as the _monolithic template had it. Size is also throughput on EBS for some volume types, which is half the reason for the split: image layers and container filesystems stop competing with the root volume's quota"

  validation {
    condition     = var.container_volume_size >= 4 && var.container_volume_size <= 16384
    error_message = "container_volume_size must be between 4 and 16384 GiB."
  }
}
variable "container_volume_type" {
  type        = string
  default     = "gp3"
  description = "EBS volume type for the container runtime volume. gp3 as the _monolithic template had it, whose baseline 3000 IOPS and 125 MiB/s are independent of size - unlike gp2, where a small volume also means a small IOPS budget, which would undo the point of separating it"

  validation {
    condition     = contains(["gp2", "gp3", "io1", "io2", "st1", "sc1"], var.container_volume_type)
    error_message = "container_volume_type must be one of: gp2, gp3, io1, io2, st1, sc1."
  }
}
variable "container_volume_encrypted" {
  type        = bool
  default     = true
  description = "Whether the container runtime volume is encrypted at rest. True, where the _monolithic template had it false. Every image layer and every container's writable filesystem lives on this volume, so it holds whatever the workloads write; the EC2 service encrypts it with the account's default EBS key at launch, which costs nothing and needs no extra IAM on the node role"
}
variable "container_data_path" {
  type        = string
  default     = "/var/lib/containerd"
  description = "Directory the container runtime keeps its state in, and therefore the mount point for the separate volume. /var/lib/containerd is where containerd stores image layers and container filesystems on the EKS-optimized AMIs. Moving it is the whole point of the project: on the root volume, a workload writing to its own filesystem or to stdout spends the same I/O budget the kubelet and the operating system need"

  validation {
    condition     = can(regex("^/[^ ]*[^/ ]$", var.container_data_path))
    error_message = "container_data_path must be an absolute path with no trailing slash and no spaces; it is written into /etc/fstab, where a space separates fields."
  }
}
variable "node_timezone" {
  type        = string
  default     = "Asia/Seoul"
  description = "Time zone set on each node, as the _monolithic template did. Cosmetic - it only changes how local timestamps in node-level logs read, since Kubernetes and CloudWatch both work in UTC regardless"

  validation {
    condition     = can(regex("^[A-Za-z]+(/[A-Za-z_+-]+)+$|^UTC$", var.node_timezone))
    error_message = "node_timezone must be a tz database name such as Asia/Seoul, or UTC."
  }
}
variable "allow_inbound_from_anywhere" {
  type        = bool
  default     = true
  description = "Whether the VS Code security group accepts traffic from 0.0.0.0/0 on the code-server port. True as the _monolithic template had it, because code-server is reached from a browser - but it runs with authentication disabled, so narrow this to your own address where possible"
}
variable "vscode_instance_type" {
  type        = string
  default     = "t3.medium"
  description = "EC2 instance type for the VS Code EC2 instance"

  validation {
    condition     = can(regex("^[a-z0-9]+\\.[a-z0-9]+$", var.vscode_instance_type))
    error_message = "vscode_instance_type must be a valid EC2 instance type, e.g. t3.medium."
  }
}
variable "marker_file_path" {
  type        = string
  default     = "/run/terraform"
  description = "Directory on the VS Code instance where the bootstrap drops its completion marker. The README association waits for that marker instead of trusting depends_on (rules.md D-5/H-2)"

  validation {
    condition     = var.marker_file_path == null || can(regex("^/", var.marker_file_path))
    error_message = "marker_file_path must be an absolute path starting with '/', or null."
  }
}
variable "readme_timeout_seconds" {
  type        = number
  default     = 900
  description = "How long the README SSM association may take. It first waits for the instance bootstrap to finish, which includes downloading kubectl, eksctl and helm"

  validation {
    condition     = var.readme_timeout_seconds > 0
    error_message = "readme_timeout_seconds must be positive."
  }
}
