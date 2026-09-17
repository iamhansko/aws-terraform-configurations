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
  description = "Name of the EKS cluster. Also the middle segment of every log group Fluent Bit writes to (/aws/eks/<cluster_name>/<component>)"

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
  description = "Whether the EKS cluster API server endpoint is reachable from the public internet, so kubectl can be run from outside the VPC. Restrict access with public_access_cidrs rather than leaving it open to 0.0.0.0/0"
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
  description = "Name of the managed node group. Fluent Bit and the CloudWatch agent both run as DaemonSets on it, so it is what produces the logs this project collects"

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
  description = "Desired node count for the managed node group. More than one node makes the node-scoped Logs Insights query in the README meaningful, since there is then something to filter between"

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
variable "cloudwatch_observability_addon_version" {
  type        = string
  default     = null
  description = "Specific amazon-cloudwatch-observability addon version (e.g. v4.7.0-eksbuild.1). When null, EKS picks the default version for the cluster's Kubernetes version"

  validation {
    condition     = var.cloudwatch_observability_addon_version == null || can(regex("^v[0-9]+\\.[0-9]+\\.[0-9]+-eksbuild\\.[0-9]+$", var.cloudwatch_observability_addon_version))
    error_message = "cloudwatch_observability_addon_version must look like v4.7.0-eksbuild.1, or null."
  }
}
variable "container_log_components" {
  type = map(list(string))
  default = {
    "vpc-cni"                         = ["/var/log/containers/aws-node-*_kube-system_*.log"]
    "kube-proxy"                      = ["/var/log/containers/kube-proxy-*_kube-system_*.log"]
    "coredns"                         = ["/var/log/containers/coredns-*_kube-system_*.log"]
    "metrics-server"                  = ["/var/log/containers/metrics-server-*_kube-system_*.log"]
    "cluster-autoscaler"              = ["/var/log/containers/cluster-autoscaler-*_kube-system_*.log"]
    "aws-load-balancer-controller"    = ["/var/log/containers/aws-load-balancer-controller-*_kube-system_*.log"]
    "aws-efs-csi-driver"              = ["/var/log/containers/efs-csi-controller-*_kube-system_*.log", "/var/log/containers/efs-csi-node-*_kube-system_*.log"]
    "amazon-cloudwatch-observability" = ["/var/log/containers/amazon-cloudwatch-observability-controller-manager-*_amazon-cloudwatch_*.log", "/var/log/containers/cloudwatch-agent-*_amazon-cloudwatch_*.log", "/var/log/containers/fluent-bit-*_amazon-cloudwatch_*.log"]
  }
  description = "Per-component Fluent Bit log pipelines, keyed by component name with the container log paths to tail. Each key becomes its own log group, /aws/eks/<cluster_name>/<component>. Several defaults here (cluster-autoscaler, aws-load-balancer-controller, aws-efs-csi-driver) are for components this project does not install: a glob matching nothing costs nothing, so the pipelines are ready if the cluster later gains them"

  validation {
    condition     = length(var.container_log_components) > 0
    error_message = "container_log_components must contain at least one component."
  }
}
variable "disable_default_container_logs" {
  type        = bool
  default     = true
  description = "Whether to blank out the addon's built-in application-log.conf and dataplane-log.conf pipelines. True by default because they ship every container's stdout into two catch-all log groups, duplicating what the per-component pipelines collect and burying it in one stream"
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
