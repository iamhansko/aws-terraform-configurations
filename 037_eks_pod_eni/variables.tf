variable "aws_region" {
  type        = string
  default     = null
  description = "Target AWS region. When null, falls back to the provider default chain (AWS_REGION, profile, etc.)."
}

variable "cluster_name" {
  type        = string
  default     = "eks-pod-eni-cluster"
  description = "Name of the EKS cluster"

  validation {
    condition     = length(var.cluster_name) > 0
    error_message = "cluster_name must not be empty."
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
  description = "Whether the EKS cluster API server endpoint is reachable from the public internet. Needed because kubectl_manifest (modules/pod_security_group_policy) runs from the machine executing terraform apply, not from inside the VPC (rules.md E-1/E-2); the original _monolithic design ran kubectl from the vscode_ec2 bastion inside the VPC instead, which is why the underlying eks_cluster module still defaults this to false. Restrict access with public_access_cidrs rather than leaving this open to 0.0.0.0/0"
}

variable "public_access_cidrs" {
  type        = list(string)
  default     = ["0.0.0.0/0"]
  description = "CIDR blocks allowed to reach the EKS API server's public endpoint when endpoint_public_access is true. Set this to your current IP in CIDR form (e.g. [\"203.0.113.4/32\"]) instead of leaving the default 0.0.0.0/0, since bootstrap_cluster_creator_admin_permissions grants whoever can reach this endpoint with a valid AWS credential effectively unrestricted cluster access"

  validation {
    condition     = alltrue([for cidr in var.public_access_cidrs : can(cidrhost(cidr, 0))])
    error_message = "public_access_cidrs must contain valid IPv4 CIDR blocks."
  }
}

variable "key_name" {
  type        = string
  default     = "eks-pod-eni-key"
  description = "Name of the EC2 key pair created for the demo instances"

  validation {
    condition     = can(regex("^[ -~]{1,255}$", var.key_name))
    error_message = "key_name must be a non-empty string of printable ASCII characters, 255 characters or fewer."
  }
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
  description = "Whether to allow inbound access to the code-server port (8000) on the VS Code EC2 instance from 0.0.0.0/0. Leave false and use SSM Session Manager port forwarding for anything but a short-lived demo"
}

variable "web_instance_type" {
  type        = string
  default     = "t3.small"
  description = "EC2 instance type for the private web EC2 instance"

  validation {
    condition     = can(regex("^[a-z0-9]+\\.[a-z0-9]+$", var.web_instance_type))
    error_message = "web_instance_type must be a valid EC2 instance type (e.g. t3.small)."
  }
}

variable "node_group_instance_types" {
  type        = list(string)
  default     = ["c5.large"]
  description = "EC2 instance types for the EKS managed node group"

  validation {
    condition     = length(var.node_group_instance_types) > 0
    error_message = "node_group_instance_types must contain at least one instance type."
  }
}

variable "node_group_desired_size" {
  type        = number
  default     = 2
  description = "Desired number of worker nodes"

  validation {
    condition     = var.node_group_desired_size >= 0
    error_message = "node_group_desired_size must be zero or greater."
  }
}

variable "node_group_min_size" {
  type        = number
  default     = 2
  description = "Minimum number of worker nodes"

  validation {
    condition     = var.node_group_min_size >= 0
    error_message = "node_group_min_size must be zero or greater."
  }
}

variable "node_group_max_size" {
  type        = number
  default     = 4
  description = "Maximum number of worker nodes"

  validation {
    condition     = var.node_group_max_size >= 0
    error_message = "node_group_max_size must be zero or greater."
  }
}

variable "enable_pod_eni" {
  type        = bool
  default     = true
  description = "Whether to enable Pod ENI (branch ENI) support in the VPC CNI plugin. Required for Security Groups for Pods; this is the whole point of this project, so leave it true"
}

variable "pod_security_group_enforcing_mode" {
  type        = string
  default     = "standard"
  description = "Enforcing mode for Security Groups for Pods. 'strict' enforces only the branch ENI security groups and disables source NAT; 'standard' enforces both the primary and branch ENI security groups"

  validation {
    condition     = contains(["strict", "standard"], var.pod_security_group_enforcing_mode)
    error_message = "pod_security_group_enforcing_mode must be either 'strict' or 'standard'."
  }
}

variable "create_demo_pod" {
  type        = bool
  default     = true
  description = "Whether to create the dnsutils demo pod to verify that SecurityGroupPolicy actually attaches the pod security group"
}
