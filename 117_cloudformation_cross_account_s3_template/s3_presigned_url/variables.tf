variable "aws_region" {
  type        = string
  default     = null
  description = "Region to deploy into. Null follows the provider chain (AWS_REGION / AWS_DEFAULT_REGION), which is how the _monolithic template was run"

  validation {
    condition     = var.aws_region == null || can(regex("^[a-z]{2}(-gov)?-[a-z]+-[0-9]$", var.aws_region))
    error_message = "aws_region must be a region code such as ap-northeast-2, or null to follow the provider chain."
  }
}
variable "project_name" {
  type        = string
  default     = "s3-presigned-url"
  description = "Prefix for the names CloudFormation used to generate. Replaces the _monolithic template's stack_name and keeps its default, so the presigning function keeps its name"

  validation {
    condition     = can(regex("^[a-z0-9][a-z0-9-]{1,40}$", var.project_name))
    error_message = "project_name must be 2-41 characters of lowercase letters, digits and hyphens."
  }
}
variable "allow_inbound_from_anywhere" {
  type        = bool
  default     = false
  description = "Whether the controlled inbound rules use 0.0.0.0/0. When false (the default), they use only the public IPv4 /32 dynamically returned by my_ip_lookup_url"
}
variable "presigned_url_expires_in" {
  type        = number
  default     = 3600
  description = "Lifetime requested for the presigned URL, in seconds, as the _monolithic template had it. The URL stops working at this or at the expiry of the credentials that signed it, whichever is first"

  validation {
    condition     = var.presigned_url_expires_in >= 1 && var.presigned_url_expires_in <= 604800
    error_message = "presigned_url_expires_in must be between 1 and 604800 (seven days), SigV4's ceiling for a presigned URL."
  }
}
variable "template_path" {
  type        = string
  default     = "templates/vpc.yaml"
  description = "Path to the CloudFormation template to upload, relative to this root"

  validation {
    condition     = can(regex("\\.(ya?ml|json)$", var.template_path))
    error_message = "template_path must point at a .yaml, .yml or .json file."
  }
}
variable "stack_name" {
  type        = string
  default     = "my-stack"
  description = "Stack name the README's create-stack commands use, as the _monolithic template's README had it. The stack is created by hand from those commands, not by Terraform"

  validation {
    condition     = can(regex("^[a-zA-Z][a-zA-Z0-9-]{0,127}$", var.stack_name))
    error_message = "stack_name must start with a letter and be up to 128 characters of letters, digits and hyphens."
  }
}
variable "vscode_instance_type" {
  type        = string
  default     = "t3.medium"
  description = "Instance type for the VS Code workbench, as the _monolithic template had it"

  validation {
    condition     = can(regex("^[a-z0-9]+\\.[a-z0-9]+$", var.vscode_instance_type))
    error_message = "vscode_instance_type must be a valid EC2 instance type, e.g. t3.medium."
  }
}
variable "code_server_version" {
  type        = string
  default     = "4.102.3"
  description = "code-server release installed on the workbench. Pinned, where the _monolithic template asked the GitHub API for the latest release at boot"

  validation {
    condition     = can(regex("^[0-9]+\\.[0-9]+\\.[0-9]+$", var.code_server_version))
    error_message = "code_server_version must be a semantic version (e.g. 4.102.3)."
  }
}
variable "marker_file_path" {
  type        = string
  default     = "/run/terraform"
  description = "Directory on the workbench where the bootstrap drops its completion marker. The README association waits for that marker rather than relying on depends_on (rules.md D-5/H-2)"

  validation {
    condition     = can(regex("^/", var.marker_file_path))
    error_message = "marker_file_path must be an absolute path starting with '/'."
  }
}
variable "readme_timeout_seconds" {
  type        = number
  default     = 900
  description = "How long the README association may take. It first waits for the workbench bootstrap"

  validation {
    condition     = var.readme_timeout_seconds > 0
    error_message = "readme_timeout_seconds must be positive."
  }
}

variable "my_ip_lookup_url" {
  type        = string
  default     = "https://checkip.amazonaws.com/"
  description = "Trusted HTTPS endpoint that returns the public IPv4 address of the machine running Terraform. The address is converted to a /32 and used when an allow_inbound_from_anywhere switch is false"

  validation {
    condition     = startswith(var.my_ip_lookup_url, "https://")
    error_message = "my_ip_lookup_url must be an HTTPS URL because its response controls which source address the security groups admit."
  }
}
