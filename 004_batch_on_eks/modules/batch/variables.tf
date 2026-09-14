variable "cluster_name" {
  type        = string
  description = "Name of the EKS cluster backing the Batch compute environment"

  validation {
    condition     = length(var.cluster_name) > 0
    error_message = "cluster_name must not be empty."
  }
}

variable "cluster_arn" {
  type        = string
  description = "ARN of the EKS cluster backing the Batch compute environment"

  validation {
    condition     = can(regex("^arn:aws:eks:", var.cluster_arn))
    error_message = "cluster_arn must be a valid EKS cluster ARN."
  }
}

variable "kubernetes_namespace" {
  type        = string
  default     = "batch-default"
  description = "Kubernetes namespace AWS Batch schedules jobs into"

  validation {
    condition     = length(var.kubernetes_namespace) > 0
    error_message = "kubernetes_namespace must not be empty."
  }
}

variable "additional_kubernetes_namespaces" {
  type        = list(string)
  default     = ["batch-app"]
  description = "Additional Kubernetes namespaces to create and grant the aws-batch identity job-management RBAC in, alongside kubernetes_namespace"
}

variable "batch_username" {
  type        = string
  default     = "aws-batch"
  description = "Kubernetes username granted to the AWSServiceRoleForBatch service-linked role, both as the EKS access entry username and as the RBAC subject bound to aws-batch-cluster-role"

  validation {
    condition     = length(var.batch_username) > 0
    error_message = "batch_username must not be empty."
  }
}

variable "subnet_ids" {
  type        = list(string)
  description = "Private subnet IDs for Batch-managed EC2 nodes"

  validation {
    condition     = length(var.subnet_ids) > 0
    error_message = "subnet_ids must contain at least one subnet ID."
  }
}

variable "security_group_ids" {
  type        = list(string)
  description = "Security group IDs attached to Batch-managed EC2 nodes (typically the EKS cluster security group)"

  validation {
    condition     = length(var.security_group_ids) > 0
    error_message = "security_group_ids must contain at least one security group ID."
  }
}

variable "key_name" {
  type        = string
  description = "EC2 key pair name attached to Batch-managed EC2 nodes"

  validation {
    condition     = length(var.key_name) > 0
    error_message = "key_name must not be empty."
  }
}

variable "name_prefix" {
  type        = string
  default     = "batch"
  description = "Prefix used to name the job definition and job queue"

  validation {
    condition     = length(var.name_prefix) > 0
    error_message = "name_prefix must not be empty."
  }
}

variable "min_vcpus" {
  type        = number
  default     = 0
  description = "Minimum vCPUs the compute environment scales down to"

  validation {
    condition     = var.min_vcpus >= 0
    error_message = "min_vcpus must be zero or greater."
  }
}

variable "max_vcpus" {
  type        = number
  default     = 256
  description = "Maximum vCPUs the compute environment scales up to"

  validation {
    condition     = var.max_vcpus > 0
    error_message = "max_vcpus must be greater than zero."
  }
}

variable "allocation_strategy" {
  type        = string
  default     = "BEST_FIT_PROGRESSIVE"
  description = "Allocation strategy for the EC2 compute environment"

  validation {
    condition     = contains(["BEST_FIT", "BEST_FIT_PROGRESSIVE", "SPOT_CAPACITY_OPTIMIZED"], var.allocation_strategy)
    error_message = "allocation_strategy must be one of: BEST_FIT, BEST_FIT_PROGRESSIVE, SPOT_CAPACITY_OPTIMIZED."
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
  description = "IAM managed policy ARNs attached to the Batch node IAM role"

  validation {
    condition     = alltrue([for arn in var.node_iam_policy_arns : can(regex("^arn:aws:iam::", arn))])
    error_message = "node_iam_policy_arns must contain valid IAM policy ARNs."
  }
}

variable "job_container_image" {
  type        = string
  default     = "public.ecr.aws/amazonlinux/amazonlinux:latest"
  description = "Container image for the default Batch job definition"
}

variable "job_command" {
  type        = list(string)
  default     = ["sleep", "30"]
  description = "Container command for the default Batch job definition"
}

variable "job_cpu" {
  type        = string
  default     = "0.5"
  description = "CPU request/limit for the default Batch job definition"
}

variable "job_memory" {
  type        = string
  default     = "512Mi"
  description = "Memory request/limit for the default Batch job definition"
}

variable "job_timeout_seconds" {
  type        = number
  default     = 120
  description = "Attempt duration timeout, in seconds, for the default Batch job definition"

  validation {
    condition     = var.job_timeout_seconds >= 60
    error_message = "job_timeout_seconds must be at least 60 (the AWS Batch minimum)."
  }
}
