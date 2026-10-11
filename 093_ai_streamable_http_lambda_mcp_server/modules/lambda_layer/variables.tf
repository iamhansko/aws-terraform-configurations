variable "layer_name" {
  type        = string
  description = "Name of the layer, and the prefix of the package bucket's name. Every apply that changes the package publishes a new version under this name"

  validation {
    condition     = can(regex("^[a-zA-Z0-9-_]{1,64}$", var.layer_name))
    error_message = "layer_name must be 1-64 characters of letters, digits, hyphens and underscores."
  }
}
variable "description" {
  type        = string
  default     = null
  description = "Description of the layer version. Null leaves it unset"

  validation {
    condition     = var.description == null || length(coalesce(var.description, "-")) <= 256
    error_message = "description must be 256 characters or fewer, or null."
  }
}
variable "package_key" {
  type        = string
  default     = "layer.zip"
  description = "Key the workbench uploads the layer package to in the package bucket. layer.zip, the key the _monolithic template uploaded to"

  validation {
    # It reaches the workbench inside a shell command, so it is held to characters that need no quoting.
    condition     = can(regex("^[a-zA-Z0-9][a-zA-Z0-9/._-]*\\.zip$", var.package_key))
    error_message = "package_key must be a relative key of letters, digits and /._- ending in .zip, with no leading slash."
  }
}
variable "package_sha256" {
  type        = string
  description = "Base64-encoded SHA-256 of the package at package_key, as S3 reports it for an object uploaded with a SHA-256 checksum. It is what decides whether a new layer version is published, and passing it in is what orders the layer after the upload"

  validation {
    # Unknown until the build has run, so this is checked at apply. An empty value means the object was
    # uploaded without --checksum-algorithm SHA256.
    condition     = can(regex("^[A-Za-z0-9+/]{43}=$", var.package_sha256))
    error_message = "package_sha256 must be a base64-encoded SHA-256. If it is empty, the package was uploaded without a SHA-256 checksum - upload it with aws s3api put-object --checksum-algorithm SHA256, as the root's build association does."
  }
}
variable "compatible_runtimes" {
  type        = list(string)
  description = "Runtimes the layer declares itself compatible with. The caller passes the one runtime the package was built for, rather than a list it was not tested against"

  validation {
    condition     = length(var.compatible_runtimes) > 0 && alltrue([for runtime in var.compatible_runtimes : can(regex("^python3\\.[0-9]+$", runtime))])
    error_message = "compatible_runtimes must contain at least one Python runtime, e.g. python3.13."
  }
}
variable "compatible_architectures" {
  type        = list(string)
  description = "Instruction set architectures the layer declares itself compatible with, matching the platform the package was built for"

  validation {
    condition     = length(var.compatible_architectures) > 0 && alltrue([for arch in var.compatible_architectures : contains(["x86_64", "arm64"], arch)])
    error_message = "compatible_architectures must contain x86_64, arm64 or both."
  }
}
