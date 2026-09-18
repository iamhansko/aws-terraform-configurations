variable "name" {
  type        = string
  default     = "firehose-deliverystream"
  description = "Name of the Firehose delivery stream. Fluent Bit names it in the OUTPUT block's delivery_stream field, so this value reaches the cluster as configuration"

  validation {
    condition     = can(regex("^[a-zA-Z0-9_.-]{1,64}$", var.name))
    error_message = "name must be 1-64 characters of letters, digits, underscores, dots or hyphens - the set Firehose accepts for a delivery stream name."
  }
}
variable "bucket_prefix" {
  type        = string
  default     = "stem-fargate-logs-"
  description = "Prefix for the generated destination bucket name. A prefix rather than a fixed name because S3 bucket names are globally unique, so a literal name makes the project undeployable a second time"

  validation {
    condition     = can(regex("^[a-z0-9][a-z0-9.-]{1,37}$", var.bucket_prefix))
    error_message = "bucket_prefix must be lowercase alphanumeric with dots or hyphens, 2-38 characters, and must start with a letter or digit. S3 appends a suffix, so the prefix has to leave room inside the 63-character limit."
  }
}
variable "force_destroy" {
  type        = bool
  default     = true
  description = "Whether terraform destroy may delete the bucket while it still holds objects. True because Firehose will have written log files into it, and S3 refuses to delete a non-empty bucket - leaving the destroy stuck until someone empties it by hand. Set false if the delivered logs are worth keeping"
}
variable "policy_name" {
  type        = string
  default     = "FirehoseS3Policy"
  description = "Name of the inline policy on the Firehose role"

  validation {
    condition     = can(regex("^[a-zA-Z0-9+=,.@_-]{1,128}$", var.policy_name))
    error_message = "policy_name must be 1-128 characters from the set IAM accepts for a policy name."
  }
}
variable "buffering_size_mb" {
  type        = number
  default     = 5
  description = "How much data Firehose accumulates before writing an S3 object. The 5 MB default means a low-volume demo waits for the interval below instead, which is why that interval matters more here"

  validation {
    condition     = var.buffering_size_mb >= 1 && var.buffering_size_mb <= 128
    error_message = "buffering_size_mb must be between 1 and 128, the range Firehose accepts for an S3 destination."
  }
}
variable "buffering_interval_seconds" {
  type        = number
  default     = 60
  description = "How long Firehose waits before writing an object even if the size threshold is not met. 60 rather than the 300-second default: at demo volumes nothing would appear in the bucket for five minutes, which reads as a broken pipeline"

  validation {
    condition     = var.buffering_interval_seconds >= 0 && var.buffering_interval_seconds <= 900
    error_message = "buffering_interval_seconds must be between 0 and 900, the range Firehose accepts."
  }
}
variable "error_output_prefix" {
  type        = string
  default     = "error"
  description = "Key prefix under which Firehose writes records it could not deliver. Declared explicitly because the service defaults this field to 'error' when it is omitted, which leaves an omitted value showing up as a permanent 'error' -> null diff on every plan"

  validation {
    condition     = length(var.error_output_prefix) > 0
    error_message = "error_output_prefix must not be empty. S3 accepts an empty prefix, but then failed records land next to the delivered ones and stop being distinguishable."
  }
}
variable "enable_cloudwatch_logging" {
  type        = bool
  default     = true
  description = "Whether Firehose writes its own delivery errors to CloudWatch Logs. True by default because the role already carries logs:PutLogEvents for this purpose, and with it off a delivery that fails on the destination side is silent - the records are simply gone and neither the bucket nor the stream's metrics say why"
}
variable "log_retention_days" {
  type        = number
  default     = 7
  description = "Retention on the delivery-error log group. Short because these are demo diagnostics, and an unset retention means never expire"

  validation {
    condition     = contains([1, 3, 5, 7, 14, 30, 60, 90, 120, 150, 180, 365, 400, 545, 731, 1096, 1827, 2192, 2557, 2922, 3288, 3653], var.log_retention_days)
    error_message = "log_retention_days must be one of the retention values CloudWatch Logs accepts."
  }
}
variable "compression_format" {
  type        = string
  default     = "UNCOMPRESSED"
  description = "Compression applied to the delivered objects. UNCOMPRESSED so the demo can read a delivered file with 'aws s3 cp - | cat' and see JSON; GZIP is the right choice for anything real"

  validation {
    condition     = contains(["UNCOMPRESSED", "GZIP", "ZIP", "Snappy", "HADOOP_SNAPPY"], var.compression_format)
    error_message = "compression_format must be one of: UNCOMPRESSED, GZIP, ZIP, Snappy, HADOOP_SNAPPY."
  }
}
variable "enable_kinesis_source_access" {
  type        = bool
  default     = false
  description = "Whether the Firehose role may read from Kinesis data streams. The _monolithic template granted this unconditionally on stream/*, but this delivery stream's source is direct PUT from Fluent Bit, so it reads from no stream at all. Turn on only if the stream is reconfigured to have a Kinesis source"
}
variable "enable_s3_kms_access" {
  type        = bool
  default     = false
  description = "Whether the Firehose role may use KMS keys to write encrypted objects. The _monolithic template granted this unconditionally on key/*, but the destination bucket here has no SSE-KMS configuration, so nothing uses it. Turn on together with a bucket encryption configuration"
}
variable "enable_lambda_transform_access" {
  type        = bool
  default     = false
  description = "Whether the Firehose role may invoke Lambda functions. The _monolithic template granted this unconditionally on function:*:*, but this delivery stream declares no transform, so it invokes nothing. Turn on when adding a processing_configuration"
}
