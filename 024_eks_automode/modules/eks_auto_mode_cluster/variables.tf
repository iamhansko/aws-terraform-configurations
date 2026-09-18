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
  default     = "1.33"
  description = "EKS cluster Kubernetes version (1.XX)"

  validation {
    condition     = contains(["1.31", "1.32", "1.33"], var.kubernetes_version)
    error_message = "kubernetes_version must be one of: 1.31, 1.32, 1.33."
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
  type = list(string)
  default = [
    "arn:aws:iam::aws:policy/AmazonEKSClusterPolicy",
    "arn:aws:iam::aws:policy/AmazonEKSComputePolicy",
    "arn:aws:iam::aws:policy/AmazonEKSNetworkingPolicy",
    "arn:aws:iam::aws:policy/AmazonEKSLoadBalancingPolicy",
    "arn:aws:iam::aws:policy/AmazonEKSBlockStoragePolicy",
  ]
  description = "Managed policies attached to the cluster role. Five rather than the one a normal cluster needs: Auto Mode acts on the account's behalf to launch nodes, manage load balancers and provision volumes, so the cluster role carries the permission for each capability. Attached with for_each rather than one resource per policy (rules.md B-7)"

  validation {
    condition     = alltrue([for arn in var.cluster_iam_policy_arns : can(regex("^arn:aws:iam::", arn))])
    error_message = "cluster_iam_policy_arns must contain valid IAM policy ARNs."
  }
  validation {
    condition     = contains(var.cluster_iam_policy_arns, "arn:aws:iam::aws:policy/AmazonEKSClusterPolicy")
    error_message = "cluster_iam_policy_arns must include AmazonEKSClusterPolicy. EKS rejects a cluster whose role lacks it, and the failure arrives minutes into the create."
  }
}
variable "node_iam_policy_arns" {
  type = list(string)
  default = [
    "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryPullOnly",
    "arn:aws:iam::aws:policy/AmazonEKSWorkerNodeMinimalPolicy",
  ]
  description = "Managed policies attached to the role Auto Mode's nodes carry. Deliberately the two minimal ones: Auto Mode handles CNI and kube-proxy itself, so the nodes need neither AmazonEKS_CNI_Policy nor the full AmazonEKSWorkerNodePolicy that a managed node group requires. PullOnly rather than ReadOnly for ECR, because the nodes pull images and never push"

  validation {
    condition     = alltrue([for arn in var.node_iam_policy_arns : can(regex("^arn:aws:iam::", arn))])
    error_message = "node_iam_policy_arns must contain valid IAM policy ARNs."
  }
}
variable "compute_enabled" {
  type        = bool
  default     = true
  description = "Whether Auto Mode manages compute. This is what makes the cluster Auto Mode - with it off the cluster has no way to run a pod, because the project declares no node group and no Fargate profile"

  validation {
    condition     = var.compute_enabled
    error_message = "compute_enabled must be true in this configuration. Nothing else here provides capacity - there is no managed node group and no Fargate profile - so a cluster with Auto Mode compute off would come up unable to schedule anything, including CoreDNS."
  }
}
variable "node_pools" {
  type        = list(string)
  default     = ["general-purpose", "system"]
  description = "Auto Mode node pools to enable. general-purpose carries the workload; system carries the cluster's own components and is what CoreDNS lands on"

  validation {
    condition     = alltrue([for pool in var.node_pools : contains(["general-purpose", "system"], pool)])
    error_message = "node_pools may only contain general-purpose and system, the two built-in Auto Mode pools."
  }
  validation {
    condition     = contains(var.node_pools, "system")
    error_message = "node_pools must include \"system\". Without it the cluster's own components, CoreDNS among them, have no pool to be scheduled onto and DNS never comes up."
  }
}
variable "elastic_load_balancing_enabled" {
  type        = bool
  default     = true
  description = "Whether Auto Mode runs its built-in load balancing controller. This is what replaces the AWS Load Balancer Controller Helm release the other EKS projects in this repository install themselves"
}
variable "block_storage_enabled" {
  type        = bool
  default     = true
  description = "Whether Auto Mode runs its built-in EBS CSI driver, so a PersistentVolumeClaim is fulfilled without installing a driver"
}
variable "ip_family" {
  type        = string
  default     = "ipv4"
  description = "Address family for pod and service networking"

  validation {
    condition     = contains(["ipv4", "ipv6"], var.ip_family)
    error_message = "ip_family must be either ipv4 or ipv6."
  }
}
variable "service_ipv4_cidr" {
  type        = string
  default     = "10.100.0.0/16"
  description = "CIDR the cluster allocates Service addresses from. Must not overlap the VPC CIDR - EKS rejects an overlapping range, and 10.100.0.0/16 is chosen so it does not collide with the 10.0.0.0/16 VPC"

  validation {
    condition     = can(cidrhost(var.service_ipv4_cidr, 0))
    error_message = "service_ipv4_cidr must be a valid IPv4 CIDR block."
  }
}
