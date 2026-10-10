variable "aws_region" {
  type        = string
  default     = null
  description = "Region the VPC, the instance and the bucket are created in. Null follows the provider chain (AWS_REGION / AWS_DEFAULT_REGION), which is how the _monolithic template was run. The Lambda@Edge functions go to us-east-1 regardless, through their own provider"

  validation {
    condition     = var.aws_region == null || can(regex("^[a-z]{2}(-gov)?-[a-z]+-[0-9]$", var.aws_region))
    error_message = "aws_region must be a region code such as ap-northeast-2, or null to follow the provider chain."
  }
}
variable "project_name" {
  type        = string
  default     = "nodejs"
  description = "Prefix of the two function names. Replaces the _monolithic template's stack_name and keeps its default, so the functions keep their names (nodejs-s3-origin-lambda-function and nodejs-ec2-origin-lambda-function). Function names are unique per account and region, so a second copy of this project in the account needs a different value"

  validation {
    condition     = can(regex("^[a-zA-Z0-9-_]{1,23}$", var.project_name))
    error_message = "project_name must be 1-23 characters of letters, digits, hyphens and underscores."
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
variable "lambda_runtime" {
  type        = string
  default     = "nodejs22.x"
  description = "Runtime of both Lambda@Edge functions, as the _monolithic template had it"

  validation {
    condition     = can(regex("^nodejs[0-9]+\\.x$", var.lambda_runtime))
    error_message = "lambda_runtime must be a Node.js runtime (e.g. nodejs22.x)."
  }
}
variable "lambda_delete_timeout" {
  type        = string
  default     = "60m"
  description = "How long terraform destroy waits for CloudFront to remove a function's edge replicas before giving up on deleting it"

  validation {
    condition     = can(regex("^[0-9]+(m|h)$", var.lambda_delete_timeout))
    error_message = "lambda_delete_timeout must be a duration in minutes or hours, such as 60m or 2h."
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
