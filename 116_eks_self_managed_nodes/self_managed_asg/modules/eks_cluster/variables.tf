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
  description = "EKS control plane log types to enable in CloudWatch Logs"

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

variable "ip_family" {
  type        = string
  default     = "ipv4"
  description = "IP family the cluster assigns Service and pod addresses from"

  validation {
    condition     = contains(["ipv4", "ipv6"], var.ip_family)
    error_message = "ip_family must be either ipv4 or ipv6."
  }
}

variable "service_ipv4_cidr" {
  type        = string
  default     = "172.20.0.0/16"
  description = "CIDR the cluster allocates Kubernetes Service addresses from. Stated explicitly rather than left to the EKS default because a self-managed node has to be told it: its NodeConfig carries both this block and the cluster DNS address inside it, and there is no bootstrap script to discover them. Changing it forces cluster replacement"

  validation {
    condition     = can(cidrhost(var.service_ipv4_cidr, 0))
    error_message = "service_ipv4_cidr must be a valid IPv4 CIDR block."
  }
}

variable "cluster_dns_host_number" {
  type        = number
  default     = 10
  description = "Host number inside service_ipv4_cidr that the cluster DNS Service is given. Ten, which is what EKS assigns, and the value a self-managed node's kubelet has to be told - a wrong one produces nodes that join Ready and pods that resolve nothing"

  validation {
    condition     = var.cluster_dns_host_number > 0
    error_message = "cluster_dns_host_number must be greater than zero."
  }
}
