variable "bucket" {
  type        = string
  description = "Name of the S3 bucket the source directory is synced into"

  validation {
    condition     = can(regex("^[a-z0-9][a-z0-9.-]{1,61}[a-z0-9]$", var.bucket))
    error_message = "bucket must be a valid S3 bucket name (3-63 lowercase characters, digits, dots and hyphens)."
  }
}
variable "bucket_arn" {
  type        = string
  description = "ARN of the target bucket, used to scope the function's IAM policy to that bucket only. Passed in rather than derived from the name so this module never has to look the bucket up itself"

  validation {
    condition     = can(regex("^arn:aws[a-z-]*:s3:::", var.bucket_arn))
    error_message = "bucket_arn must be a valid S3 bucket ARN (e.g. arn:aws:s3:::my-bucket)."
  }
}
variable "source_dir" {
  type        = string
  description = "Directory whose tree is uploaded, recursively. Terraform's fileset/filebase64 resolve a relative path against the directory terraform runs in, not against this module, so the caller should prefix it with path.root or path.module before passing it here"

  validation {
    condition     = length(var.source_dir) > 0
    error_message = "source_dir must not be empty."
  }
}
variable "key_prefix" {
  type        = string
  default     = ""
  description = "Prefix prepended to every object key. Empty means the directory's contents land at the bucket root, mirroring 'aws s3 sync <dir> s3://<bucket>'. Combined with delete_removed = true this makes the whole bucket a mirror of source_dir, so anything else in it is deleted - set a prefix when the bucket holds other data. Include the trailing slash"

  validation {
    condition     = var.key_prefix == "" || can(regex("^[^/].*/$", var.key_prefix))
    error_message = "key_prefix must be empty, or a path not starting with '/' and ending with '/' (e.g. 'assets/')."
  }
}
variable "file_pattern" {
  type        = string
  default     = "**"
  description = "Glob selecting which files to upload. Must be '**' (not '*') to recurse: a single '*' matches only entries directly inside source_dir"

  validation {
    condition     = length(var.file_pattern) > 0
    error_message = "file_pattern must not be empty."
  }
}
variable "exclude_patterns" {
  type        = list(string)
  default     = ["**/.DS_Store", ".DS_Store", "**/Thumbs.db", "Thumbs.db"]
  description = "Globs subtracted from the selected files, the equivalent of 'aws s3 sync --exclude'. Each is matched against source_dir the same way file_pattern is"
}
variable "delete_removed" {
  type        = bool
  default     = true
  description = "Whether objects under key_prefix that source_dir no longer contains are deleted, the equivalent of 'aws s3 sync --delete'. When false, removing a local file leaves its object behind"
}
variable "delete_on_destroy" {
  type        = bool
  default     = true
  description = "Whether terraform destroy invokes the function once more to delete the objects it uploaded. Without this the objects survive the destroy and the bucket cannot be removed unless it has force_destroy set"
}
variable "function_name" {
  type        = string
  default     = "s3-sync-lambda"
  description = "Name of the Lambda function. Also determines the CloudWatch log group name, so it has to be explicit rather than provider-generated"

  validation {
    condition     = can(regex("^[a-zA-Z0-9-_]{1,64}$", var.function_name))
    error_message = "function_name must be 64 characters or fewer of letters, digits, hyphens and underscores."
  }
}
variable "runtime" {
  type        = string
  default     = "python3.14"
  description = "Lambda runtime. The handler only needs boto3, which every managed Python runtime provides"

  validation {
    condition     = contains(["python3.12", "python3.13", "python3.14"], var.runtime)
    error_message = "runtime must be one of: python3.12, python3.13, python3.14."
  }
}
variable "timeout" {
  type        = number
  default     = 900
  description = "Function timeout in seconds. The sync is sequential, so this bounds how many files one invocation can transfer; 900 is the Lambda maximum"

  validation {
    condition     = var.timeout >= 1 && var.timeout <= 900
    error_message = "timeout must be between 1 and 900 seconds."
  }
}
variable "memory_size" {
  type        = number
  default     = 256
  description = "Function memory in MB. Also scales the CPU and network share the function gets, so raising it speeds up large syncs"

  validation {
    condition     = var.memory_size >= 128 && var.memory_size <= 10240
    error_message = "memory_size must be between 128 and 10240 MB."
  }
}
variable "log_retention_in_days" {
  type        = number
  default     = 7
  description = "How long the function's CloudWatch logs are kept. The default avoids the 'never expire' setting Lambda would otherwise use when it creates the log group itself"

  validation {
    condition     = contains([1, 3, 5, 7, 14, 30, 60, 90, 120, 150, 180, 365, 400, 545, 731, 1096, 1827, 2192, 2557, 2922, 3288, 3653, 0], var.log_retention_in_days)
    error_message = "log_retention_in_days must be a value CloudWatch Logs accepts (1, 3, 5, 7, 14, 30, 60, 90, ... 3653), or 0 to never expire."
  }
}
variable "payload_directory_name" {
  type        = string
  default     = "payload"
  description = "Directory inside the deployment package that holds the bundled source tree. Passed to the handler as the PAYLOAD_DIRECTORY environment variable, so the two cannot disagree"

  validation {
    condition     = can(regex("^[A-Za-z0-9_-]+$", var.payload_directory_name))
    error_message = "payload_directory_name must be a single path segment of letters, digits, hyphens and underscores."
  }
}
variable "content_types" {
  type = map(string)
  default = {
    css   = "text/css"
    csv   = "text/csv"
    gif   = "image/gif"
    htm   = "text/html"
    html  = "text/html"
    ico   = "image/x-icon"
    jpeg  = "image/jpeg"
    jpg   = "image/jpeg"
    js    = "application/javascript"
    json  = "application/json"
    map   = "application/json"
    md    = "text/markdown"
    mjs   = "application/javascript"
    pdf   = "application/pdf"
    png   = "image/png"
    svg   = "image/svg+xml"
    txt   = "text/plain"
    webp  = "image/webp"
    woff  = "font/woff"
    woff2 = "font/woff2"
    xml   = "application/xml"
    yaml  = "application/yaml"
    yml   = "application/yaml"
    zip   = "application/zip"
  }
  description = "Maps a lowercased file extension to the Content-Type stored on the object. Extensions not listed here fall back to default_content_type"

  validation {
    condition     = alltrue([for extension in keys(var.content_types) : can(regex("^[a-z0-9]+$", extension))])
    error_message = "content_types keys must be lowercase alphanumeric file extensions, without a leading dot."
  }
}
variable "default_content_type" {
  type        = string
  default     = "application/octet-stream"
  description = "Content-Type used for files whose extension is not in content_types"

  validation {
    condition     = can(regex("^[a-z0-9.+-]+/[a-z0-9.+-]+$", var.default_content_type))
    error_message = "default_content_type must look like a MIME type (e.g. application/octet-stream)."
  }
}
