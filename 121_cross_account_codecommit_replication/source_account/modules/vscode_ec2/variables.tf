variable "name" {
  type        = string
  description = "Name tag and prefix for generated IAM names."

  validation {
    condition     = can(regex("^[A-Za-z0-9+=,.@_-]{1,37}$", var.name))
    error_message = "name must be 1-37 IAM-compatible characters, leaving room for Terraform's generated role-name suffix."
  }
}

variable "vpc_id" {
  type        = string
  description = "VPC ID where the workbench security group is created."

  validation {
    condition     = can(regex("^vpc-[0-9a-f]+$", var.vpc_id))
    error_message = "vpc_id must be a valid VPC ID."
  }
}

variable "subnet_id" {
  type        = string
  description = "Public subnet ID where the workbench is launched."

  validation {
    condition     = can(regex("^subnet-[0-9a-f]+$", var.subnet_id))
    error_message = "subnet_id must be a valid subnet ID."
  }
}

variable "key_name" {
  type        = string
  default     = null
  description = "Optional EC2 key-pair name."

  validation {
    condition     = var.key_name == null || can(regex("^[ -~]{1,255}$", var.key_name))
    error_message = "key_name must be 1-255 printable ASCII characters, or null."
  }
}

variable "instance_type" {
  type        = string
  description = "EC2 instance type for the workbench."

  validation {
    condition     = can(regex("^[a-z0-9]+\\.[a-z0-9]+$", var.instance_type))
    error_message = "instance_type must be a valid EC2 instance type."
  }
}

variable "ami_ssm_parameter_name" {
  type        = string
  description = "SSM parameter path resolving to the workbench AMI."

  validation {
    condition     = can(regex("^/", var.ami_ssm_parameter_name))
    error_message = "ami_ssm_parameter_name must be an absolute SSM parameter path."
  }
}

variable "root_volume_size" {
  type        = number
  description = "Encrypted gp3 root volume size in GiB."

  validation {
    condition     = var.root_volume_size >= 8 && var.root_volume_size <= 16384
    error_message = "root_volume_size must be between 8 and 16384 GiB."
  }
}

variable "code_server_version" {
  type        = string
  description = "Pinned code-server release version."

  validation {
    condition     = can(regex("^[0-9]+\\.[0-9]+\\.[0-9]+$", var.code_server_version))
    error_message = "code_server_version must be a three-part semantic version."
  }
}

variable "code_server_port" {
  type        = number
  description = "TCP port code-server binds to."

  validation {
    condition     = var.code_server_port >= 1 && var.code_server_port <= 65535
    error_message = "code_server_port must be between 1 and 65535."
  }
}

variable "security_group_name_prefix" {
  type        = string
  description = "Generated name prefix for the workbench security group."

  validation {
    condition     = can(regex("^[a-zA-Z0-9 ._:/()#,@\\[\\]+=&;{}!$*-]{1,200}$", var.security_group_name_prefix)) && !startswith(var.security_group_name_prefix, "sg-")
    error_message = "security_group_name_prefix must use the EC2 security-group character set, contain no apostrophe, and not start with sg-."
  }
}

variable "allow_inbound_from_anywhere" {
  type        = bool
  description = "Whether 0.0.0.0/0 may reach code_server_port."
}

variable "ingress_prefix_list_ids" {
  type        = list(string)
  default     = []
  description = "Static managed prefix-list IDs allowed to reach code-server."

  validation {
    condition     = alltrue([for id in var.ingress_prefix_list_ids : can(regex("^pl-[0-9a-f]+$", id))])
    error_message = "ingress_prefix_list_ids must contain valid managed prefix-list IDs."
  }
}

variable "associate_public_ip_address" {
  type        = bool
  default     = true
  description = "Whether the workbench receives a public IPv4 address."
}

variable "iam_policy_arns" {
  type        = list(string)
  description = "Static managed-policy ARNs attached to the human workbench role."

  validation {
    condition     = length(var.iam_policy_arns) > 0 && alltrue([for arn in var.iam_policy_arns : can(regex("^arn:[a-z0-9-]+:iam::aws:policy/", arn))])
    error_message = "iam_policy_arns must contain AWS managed-policy ARNs."
  }
}

variable "extra_security_group_ids" {
  type        = list(string)
  default     = []
  description = "Additional security group IDs attached to the instance."

  validation {
    condition     = alltrue([for id in var.extra_security_group_ids : can(regex("^sg-[0-9a-f]+$", id))])
    error_message = "extra_security_group_ids must contain valid security group IDs."
  }
}

variable "marker_file_path" {
  type        = string
  default     = null
  description = "Optional absolute directory where the userdata completion marker is created."

  validation {
    condition     = var.marker_file_path == null || can(regex("^/", var.marker_file_path))
    error_message = "marker_file_path must be an absolute path, or null."
  }
}

variable "additional_user_data" {
  type        = string
  default     = ""
  description = "Additional shell commands run before the userdata completion marker is created."

  validation {
    condition     = length(var.additional_user_data) < 12000
    error_message = "additional_user_data must stay below 12000 characters to fit EC2 user-data limits."
  }
}
