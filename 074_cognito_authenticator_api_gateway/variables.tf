variable "aws_region" {
  type        = string
  default     = null
  description = "Region to deploy into. Null follows the provider chain (AWS_REGION / AWS_DEFAULT_REGION), which is how the _monolithic template was run"

  validation {
    condition     = var.aws_region == null || can(regex("^[a-z]{2}(-gov)?-[a-z]+-[0-9]$", var.aws_region))
    error_message = "aws_region must be a region code such as ap-northeast-2, or null to follow the provider chain."
  }
}
variable "webapp_name" {
  type        = string
  default     = "cognito-authenticator-webapp"
  description = "Name of the workshop web app's REST API, and the prefix of its function (<name>-CognitoWebApp) and package bucket. It replaces the SAM stack name, which named both. The _monolithic template's stack was cognito-webapp, and so was 073_cognito_identity_pool's - so the second of the two applied into one account redeployed the first one's web app. Each project has its own default"

  validation {
    # The function name is limited to 64 characters, and "-CognitoWebApp" takes 14 of them.
    condition     = can(regex("^[a-zA-Z][a-zA-Z0-9-]{0,49}$", var.webapp_name))
    error_message = "webapp_name must start with a letter and be up to 50 characters of letters, digits and hyphens."
  }
}
variable "allow_inbound_from_anywhere" {
  type        = bool
  default     = true
  description = "Whether code-server accepts traffic from 0.0.0.0/0. True as the _monolithic template had it - a bool where that template used a string validated against [\"True\", \"False\"]. code-server has no authentication in front of it"
}
variable "vscode_instance_type" {
  type        = string
  default     = "t3.medium"
  description = "Instance type for the VS Code workbench, as the _monolithic template had it. The web app's npm installs and, once the exercise has content, its esbuild bundle run on it"

  validation {
    condition     = can(regex("^[a-z0-9]+\\.[a-z0-9]+$", var.vscode_instance_type))
    error_message = "vscode_instance_type must be a valid EC2 instance type, e.g. t3.medium."
  }
}
variable "code_server_version" {
  type        = string
  default     = "4.106.2"
  description = "code-server release installed on the workbench, as the _monolithic template pinned it"

  validation {
    condition     = can(regex("^[0-9]+\\.[0-9]+\\.[0-9]+$", var.code_server_version))
    error_message = "code_server_version must be a semantic version (e.g. 4.106.2)."
  }
}
variable "marker_file_path" {
  type        = string
  default     = "/run/terraform"
  description = "Directory on the workbench where each step drops its completion marker. Every association waits for the previous step's marker rather than relying on depends_on (rules.md D-5/H-2)"

  validation {
    condition     = can(regex("^/", var.marker_file_path))
    error_message = "marker_file_path must be an absolute path starting with '/'."
  }
}
variable "webapp_build_timeout_seconds" {
  type        = number
  default     = 1800
  description = "How long the web app's build step may take. It includes the wait for the workbench bootstrap, which installs Node.js, and two npm installs - 3m30s from launch to package when measured. It is the build association's wait, and the timeout of the function that waits for the package, which is the wait that actually holds the apply. That function is capped at 900 seconds, the longest Lambda runs; a build slower than that fails the apply without failing the build, and the next terraform apply waits again"

  validation {
    # An integer because the waiting function's timeout is min(this, 900), and Lambda takes whole seconds.
    condition     = var.webapp_build_timeout_seconds >= 300 && floor(var.webapp_build_timeout_seconds) == var.webapp_build_timeout_seconds
    error_message = "webapp_build_timeout_seconds must be an integer of at least 300."
  }
}
variable "readme_timeout_seconds" {
  type        = number
  default     = 600
  description = "How long the README association may take. It waits for the web app's build"

  validation {
    condition     = var.readme_timeout_seconds > 0
    error_message = "readme_timeout_seconds must be positive."
  }
}
