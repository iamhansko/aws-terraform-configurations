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
  default     = "1.36"
  description = "Kubernetes version for the cluster, 1.36 as the _monolithic template's parameter defaulted to"

  validation {
    condition     = contains(["1.33", "1.34", "1.35", "1.36"], var.kubernetes_version)
    error_message = "kubernetes_version must be one of 1.33, 1.34, 1.35 or 1.36. The _monolithic template also allowed 1.32, which has since left standard support - a cluster created on it starts accruing extended support charges immediately."
  }
}
variable "subnet_ids" {
  type        = list(string)
  description = "Subnet IDs attached to the EKS cluster's VPC configuration. Private subnets only here, as the _monolithic template had it: the control plane's cross-account interfaces belong where the nodes are, and with no public endpoint there is nothing for the public subnets to do"

  validation {
    condition     = length(var.subnet_ids) >= 2 && alltrue([for s in var.subnet_ids : can(regex("^subnet-[0-9a-f]+$", s))])
    error_message = "subnet_ids must contain at least two valid subnet IDs (e.g. subnet-0123456789abcdef0) - an EKS control plane requires two availability zones."
  }
}
variable "additional_security_group_ids" {
  type        = list(string)
  default     = []
  description = "Additional security group IDs attached to the EKS-managed elastic network interfaces, on top of the cluster security group EKS creates itself"

  validation {
    condition     = alltrue([for id in var.additional_security_group_ids : can(regex("^sg-[0-9a-f]+$", id))])
    error_message = "additional_security_group_ids must contain valid security group IDs (e.g. sg-0123456789abcdef0)."
  }
}
variable "endpoint_private_access" {
  type        = bool
  default     = true
  description = "Whether the EKS cluster API server endpoint is reachable from within the VPC. True, and on this project it is the only way in at all"

  validation {
    # The pair is what can be wrong: both false leaves a cluster nothing can talk to, and EKS accepts the
    # request before rejecting it (rules.md B-1).
    condition     = var.endpoint_private_access || var.endpoint_public_access
    error_message = "endpoint_private_access and endpoint_public_access cannot both be false - the API server would be unreachable from everywhere."
  }
}
variable "endpoint_public_access" {
  type        = bool
  default     = false
  description = "Whether the EKS cluster API server endpoint is reachable from the public internet. False, as the _monolithic template had it - which is why every Kubernetes object in this project is applied by an SSM Association on the workbench rather than by a Terraform provider (rules.md E-9)"
}
variable "public_access_cidrs" {
  type        = list(string)
  default     = ["0.0.0.0/0"]
  description = "CIDR blocks allowed to reach the EKS API server's public endpoint when endpoint_public_access is true. Ignored when it is false, which is the case here"

  validation {
    condition     = alltrue([for cidr in var.public_access_cidrs : can(cidrhost(cidr, 0))])
    error_message = "public_access_cidrs must contain valid IPv4 CIDR blocks."
  }
}
variable "enabled_cluster_log_types" {
  type        = list(string)
  default     = ["api", "audit", "authenticator", "controllerManager", "scheduler"]
  description = "EKS control plane log types sent to CloudWatch Logs, all five as the _monolithic template enabled them"

  validation {
    condition = alltrue([for t in var.enabled_cluster_log_types : contains([
      "api", "audit", "authenticator", "controllerManager", "scheduler"
    ], t)])
    error_message = "enabled_cluster_log_types must be a subset of: api, audit, authenticator, controllerManager, scheduler."
  }
}
variable "ip_family" {
  type        = string
  default     = "ipv4"
  description = "IP family for the cluster's service network, as the _monolithic template's KubernetesNetworkConfig had it. Immutable after creation"

  validation {
    condition     = contains(["ipv4", "ipv6"], var.ip_family)
    error_message = "ip_family must be either ipv4 or ipv6."
  }
}
variable "service_ipv4_cidr" {
  type        = string
  default     = "172.20.0.0/16"
  description = "CIDR block the cluster allocates Service IPs from, as the _monolithic template had it. Ignored when ip_family is ipv6, because EKS rejects the pair. Immutable after creation, and it must not overlap the VPC's own block"

  validation {
    condition     = can(cidrhost(var.service_ipv4_cidr, 0))
    error_message = "service_ipv4_cidr must be a valid IPv4 CIDR block."
  }
  validation {
    # EKS only accepts a /12 to /24 drawn from one of three private ranges, and rejects anything else at create
    # time - late enough that the VPC and its subnets already exist.
    condition     = tonumber(split("/", var.service_ipv4_cidr)[1]) >= 12 && tonumber(split("/", var.service_ipv4_cidr)[1]) <= 24
    error_message = "service_ipv4_cidr must have a prefix length between /12 and /24, which is the range EKS accepts."
  }
}
variable "cluster_iam_policy_arns" {
  type        = list(string)
  default     = ["arn:aws:iam::aws:policy/AmazonEKSClusterPolicy"]
  description = "IAM managed policy ARNs attached to the EKS cluster's IAM role, as the _monolithic template had it"

  validation {
    condition     = alltrue([for arn in var.cluster_iam_policy_arns : can(regex("^arn:aws:iam::", arn))])
    error_message = "cluster_iam_policy_arns must contain valid IAM policy ARNs."
  }
}
