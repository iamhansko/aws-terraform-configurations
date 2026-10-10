variable "aws_region" {
  type        = string
  default     = null
  description = "Region the VPC, the instance and the bucket are created in. Null follows the provider chain (AWS_REGION / AWS_DEFAULT_REGION), which is how the _monolithic template was run. The distribution and its functions are global"

  validation {
    condition     = var.aws_region == null || can(regex("^[a-z]{2}(-gov)?-[a-z]+-[0-9]$", var.aws_region))
    error_message = "aws_region must be a region code such as ap-northeast-2, or null to follow the provider chain."
  }
}
variable "cloudfront_origin_facing_prefix_list_name" {
  type        = string
  default     = "com.amazonaws.global.cloudfront.origin-facing"
  description = "AWS managed prefix list of the addresses CloudFront connects to origins from"

  validation {
    condition     = startswith(var.cloudfront_origin_facing_prefix_list_name, "com.amazonaws.")
    error_message = "cloudfront_origin_facing_prefix_list_name must be an AWS managed prefix list name (com.amazonaws....)."
  }
}
variable "code_path_prefix" {
  type        = string
  default     = "/code"
  description = "Path code-server is served under, by nginx on the instance and by the distribution's EC2 origin behaviours, as the _monolithic template had it"

  validation {
    condition     = can(regex("^/[a-z0-9-]+$", var.code_path_prefix))
    error_message = "code_path_prefix must be a single path segment such as /code."
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
  default     = "4.104.2"
  description = "code-server release installed on the workbench, as the _monolithic template pinned it"

  validation {
    condition     = can(regex("^[0-9]+\\.[0-9]+\\.[0-9]+$", var.code_server_version))
    error_message = "code_server_version must be a semantic version (e.g. 4.104.2)."
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
variable "create_key_value_stores" {
  type        = bool
  default     = false
  description = "Whether each function gets a CloudFront key value store associated with it. This is the one thing the default and kvs variants of this project differ in, so it is pinned per variant rather than left free"

  validation {
    condition     = var.create_key_value_stores == false
    error_message = "create_key_value_stores must stay false in the default variant. The kvs variant (../kvs) is the same configuration with the stores, applied as its own root."
  }
}
