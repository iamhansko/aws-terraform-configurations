variable "name" {
  type        = string
  description = "Name of the REST API, and the prefix of the function's name (<name>-CognitoWebApp) and the package bucket's. Stands in for the SAM stack name, which named both"

  validation {
    # The function name is limited to 64 characters, and "-CognitoWebApp" takes 14 of them.
    condition     = can(regex("^[a-zA-Z][a-zA-Z0-9-]{0,49}$", var.name))
    error_message = "name must start with a letter and be up to 50 characters of letters, digits and hyphens."
  }
}
variable "stage_name" {
  type        = string
  default     = "Prod"
  description = "Stage the API is deployed to, and the first segment of every path in its URL. Prod, the stage SAM's implicit API deployed to"

  validation {
    condition     = can(regex("^[a-zA-Z0-9_]{1,128}$", var.stage_name))
    error_message = "stage_name must be 1-128 characters of letters, digits and underscores."
  }
}
variable "package_key" {
  type        = string
  default     = "cognito-web/web-app.zip"
  description = "Key the workbench uploads the function's package to in the package bucket"

  validation {
    # It reaches the workbench through ws-env.sh, inside double quotes.
    condition     = can(regex("^[a-zA-Z0-9][a-zA-Z0-9/._-]*\\.zip$", var.package_key))
    error_message = "package_key must be a relative key of letters, digits and /._- ending in .zip, with no leading slash."
  }
}
variable "package_sha256" {
  type        = string
  description = "Base64-encoded SHA-256 of the package at package_key, as S3 reports it for an object uploaded with a SHA-256 checksum. It is what the function's code is compared against, and passing it in is what orders the function after the upload"

  validation {
    # Unknown until the build has run, so this is checked at apply. An empty value means the object was
    # uploaded without --checksum-algorithm SHA256, by something other than deploy.sh.
    condition     = can(regex("^[A-Za-z0-9+/]{43}=$", var.package_sha256))
    error_message = "package_sha256 must be a base64-encoded SHA-256. If it is empty, the package was uploaded without a SHA-256 checksum - upload it with aws s3api put-object --checksum-algorithm SHA256, as cognito-web/deploy.sh does."
  }
}
variable "runtime" {
  type        = string
  default     = "nodejs22.x"
  description = "Lambda runtime, as the SAM template had it"

  validation {
    condition     = can(regex("^nodejs[0-9]+\\.x$", var.runtime))
    error_message = "runtime must be a Node.js runtime (e.g. nodejs22.x)."
  }
}
variable "memory_size" {
  type        = number
  default     = 1024
  description = "Memory in MB, as the SAM template had it"

  validation {
    condition     = var.memory_size >= 128 && var.memory_size <= 10240 && floor(var.memory_size) == var.memory_size
    error_message = "memory_size must be an integer between 128 and 10240."
  }
}
variable "timeout" {
  type        = number
  default     = 3
  description = "Seconds an invocation may take, as the SAM template had it. The adapter starts Express during the init phase, which this does not limit"

  validation {
    # 29 seconds is as long as API Gateway waits for a Lambda proxy integration by default.
    condition     = var.timeout >= 1 && var.timeout <= 29 && floor(var.timeout) == var.timeout
    error_message = "timeout must be an integer between 1 and 29 - API Gateway gives up on the integration after 29 seconds."
  }
}
variable "lambda_adapter_layer_version" {
  type        = number
  default     = 17
  description = "Version of AWS's LambdaAdapterLayerX86 layer, as the SAM template pinned it"

  validation {
    condition     = var.lambda_adapter_layer_version >= 1 && floor(var.lambda_adapter_layer_version) == var.lambda_adapter_layer_version
    error_message = "lambda_adapter_layer_version must be a positive integer."
  }
}
variable "log_retention_in_days" {
  type        = number
  default     = 7
  description = "Days the function's log group keeps events"

  validation {
    condition     = contains([1, 3, 5, 7, 14, 30, 60, 90, 120, 150, 180, 365], var.log_retention_in_days)
    error_message = "log_retention_in_days must be one of 1, 3, 5, 7, 14, 30, 60, 90, 120, 150, 180 or 365."
  }
}
