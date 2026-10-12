variable "name" {
  type        = string
  description = "Name of the EKS cluster"

  validation {
    condition     = length(var.name) > 0
    error_message = "name must not be empty."
  }
}

variable "kubernetes_version" {
  type        = string
  default     = "1.34"
  description = "EKS cluster Kubernetes version (1.XX). The list below is what aws eks describe-cluster-versions offers, and the default is the newest release still in standard support rather than the newest outright"

  validation {
    condition     = contains(["1.33", "1.34", "1.35", "1.36"], var.kubernetes_version)
    error_message = "kubernetes_version must be one of: 1.33, 1.34, 1.35, 1.36."
  }
}

variable "subnet_ids" {
  type        = list(string)
  description = "Subnet IDs attached to the EKS cluster's VPC configuration"

  validation {
    condition     = length(var.subnet_ids) > 0
    error_message = "subnet_ids must contain at least one subnet ID."
  }
}

variable "additional_security_group_ids" {
  type        = list(string)
  default     = []
  description = "Additional security group IDs attached to the EKS-managed elastic network interfaces, on top of the cluster security group EKS creates itself. Used to let specific callers (e.g. a bastion) reach the private API server endpoint"

  validation {
    condition     = alltrue([for id in var.additional_security_group_ids : can(regex("^sg-[0-9a-f]+$", id))])
    error_message = "additional_security_group_ids must contain valid security group IDs (e.g. sg-0123456789abcdef0)."
  }
}
variable "endpoint_private_access" {
  type        = bool
  default     = true
  description = "Whether the EKS cluster API server endpoint is reachable from within the VPC"
}

variable "endpoint_public_access" {
  type        = bool
  default     = false
  description = "Whether the EKS cluster API server endpoint is reachable from the public internet"
}

variable "public_access_cidrs" {
  type        = list(string)
  default     = ["0.0.0.0/0"]
  description = "CIDR blocks allowed to reach the EKS API server's public endpoint when endpoint_public_access is true. Ignored when endpoint_public_access is false"

  validation {
    condition     = alltrue([for cidr in var.public_access_cidrs : can(cidrhost(cidr, 0))])
    error_message = "public_access_cidrs must contain valid IPv4 CIDR blocks."
  }
}

variable "enabled_cluster_log_types" {
  type        = list(string)
  default     = ["api", "audit", "authenticator", "controllerManager", "scheduler"]
  description = "EKS control plane log types to enable in CloudWatch Logs. Empty turns control plane logging off, and the log group is then not created either"

  validation {
    condition = alltrue([for t in var.enabled_cluster_log_types : contains([
      "api", "audit", "authenticator", "controllerManager", "scheduler"
    ], t)])
    error_message = "enabled_cluster_log_types must be a subset of: api, audit, authenticator, controllerManager, scheduler."
  }
}
variable "cluster_iam_policy_arns" {
  type        = list(string)
  default     = ["arn:aws:iam::aws:policy/AmazonEKSClusterPolicy"]
  description = "IAM managed policy ARNs attached to the EKS cluster's IAM role. Add AmazonEKSVPCResourceController when the cluster needs Security Groups for Pods"

  validation {
    condition     = alltrue([for arn in var.cluster_iam_policy_arns : can(regex("^arn:aws:iam::", arn))])
    error_message = "cluster_iam_policy_arns must contain valid IAM policy ARNs."
  }
}
variable "log_retention_days" {
  type        = number
  default     = 90
  description = "Retention on the control plane log group. Left to EKS the group would never expire"

  validation {
    condition     = contains([1, 3, 5, 7, 14, 30, 60, 90, 120, 150, 180, 365, 400, 545, 731, 1096, 1827, 2192, 2557, 2922, 3288, 3653], var.log_retention_days)
    error_message = "log_retention_days must be one of the retention values CloudWatch Logs accepts."
  }
}
