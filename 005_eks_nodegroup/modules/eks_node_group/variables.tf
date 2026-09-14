variable "cluster_name" {
  type        = string
  description = "Name of the EKS cluster this node group joins"

  validation {
    condition     = length(var.cluster_name) > 0
    error_message = "cluster_name must not be empty."
  }
}

variable "node_group_name" {
  type        = string
  default     = "stem-app"
  description = "Name of the EKS managed node group"

  validation {
    condition     = length(var.node_group_name) > 0
    error_message = "node_group_name must not be empty."
  }
}

variable "ami_type" {
  type        = string
  default     = "AL2023_x86_64_STANDARD"
  description = "AMI type for the node group"

  validation {
    condition = contains([
      "AL2023_x86_64_STANDARD", "AL2023_ARM_64_STANDARD", "AL2_x86_64", "AL2_x86_64_GPU", "AL2_ARM_64",
      "BOTTLEROCKET_ARM_64", "BOTTLEROCKET_x86_64", "BOTTLEROCKET_ARM_64_NVIDIA", "BOTTLEROCKET_x86_64_NVIDIA",
      "WINDOWS_CORE_2019_x86_64", "WINDOWS_FULL_2019_x86_64", "WINDOWS_CORE_2022_x86_64", "WINDOWS_FULL_2022_x86_64",
      "CUSTOM"
    ], var.ami_type)
    error_message = "ami_type must be a valid EKS node group AMI type."
  }
}

variable "instance_types" {
  type        = list(string)
  default     = ["t3.medium"]
  description = "EC2 instance types for the node group"

  validation {
    condition     = length(var.instance_types) > 0 && alltrue([for t in var.instance_types : can(regex("^[a-z0-9]+\\.[a-z0-9]+$", t))])
    error_message = "instance_types must be a non-empty list of valid EC2 instance types (e.g. t3.medium)."
  }
}

variable "capacity_type" {
  type        = string
  default     = "ON_DEMAND"
  description = "Capacity type for the node group"

  validation {
    condition     = contains(["ON_DEMAND", "SPOT"], var.capacity_type)
    error_message = "capacity_type must be either ON_DEMAND or SPOT."
  }
}

variable "desired_size" {
  type        = number
  default     = 2
  description = "Desired number of worker nodes"

  validation {
    condition     = var.desired_size >= 0
    error_message = "desired_size must be zero or greater."
  }
}

variable "min_size" {
  type        = number
  default     = 2
  description = "Minimum number of worker nodes"

  validation {
    condition     = var.min_size >= 0
    error_message = "min_size must be zero or greater."
  }
}

variable "max_size" {
  type        = number
  default     = 4
  description = "Maximum number of worker nodes"

  validation {
    condition     = var.max_size >= 0
    error_message = "max_size must be zero or greater."
  }
}

variable "labels" {
  type        = map(string)
  default     = { "stem/dedicated" = "app" }
  description = "Kubernetes labels applied to nodes in this node group"
}

variable "subnet_ids" {
  type        = list(string)
  description = "Private subnet IDs where worker nodes are launched"

  validation {
    condition     = length(var.subnet_ids) > 0
    error_message = "subnet_ids must contain at least one subnet ID."
  }
}

variable "key_name" {
  type        = string
  description = "EC2 key pair name attached to worker node instances"

  validation {
    condition     = length(var.key_name) > 0
    error_message = "key_name must not be empty."
  }
}

variable "vpc_security_group_ids" {
  type        = list(string)
  description = "Security group IDs attached to worker node instances (typically the EKS cluster security group)"

  validation {
    condition     = length(var.vpc_security_group_ids) > 0
    error_message = "vpc_security_group_ids must contain at least one security group ID."
  }
}

variable "node_iam_policy_arns" {
  type = list(string)
  default = [
    "arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy",
    "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly",
    "arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy",
    "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore",
  ]
  description = "IAM managed policy ARNs attached to the node group's IAM role"

  validation {
    condition     = alltrue([for arn in var.node_iam_policy_arns : can(regex("^arn:aws:iam::", arn))])
    error_message = "node_iam_policy_arns must contain valid IAM policy ARNs."
  }
}
