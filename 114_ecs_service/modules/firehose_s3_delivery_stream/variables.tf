variable "name" {
  type        = string
  description = "Name of the delivery stream, also used for its KMS alias and as the prefix of its IAM role name"

  validation {
    condition     = can(regex("^[a-zA-Z0-9_.-]{1,64}$", var.name))
    error_message = "name must be 1-64 characters of letters, digits, underscores, periods and hyphens - Firehose's own limit for a delivery stream name."
  }
}
variable "bucket_prefix" {
  type        = string
  default     = "stream-destination-"
  description = "Prefix for the generated destination bucket name. stream-destination- is what the _monolithic template used before the uuid slice"

  validation {
    condition     = can(regex("^[a-z0-9][a-z0-9.-]{0,36}$", var.bucket_prefix))
    error_message = "bucket_prefix must be 1-37 characters of lowercase letters, digits, periods and hyphens, starting with a letter or digit - bucket_prefix's limit, leaving room for the generated suffix."
  }
}
variable "force_destroy" {
  type        = bool
  default     = true
  description = "Whether terraform destroy empties the destination bucket first. True for a demo: Firehose writes objects Terraform does not track, and without this the destroy stops at BucketNotEmpty. The delivered logs are deleted with the bucket"
}
variable "prefix" {
  type        = string
  default     = "dst/"
  description = "Key prefix for delivered records, as the _monolithic template had it"

  validation {
    condition     = length(var.prefix) > 0 && length(var.prefix) <= 1024
    error_message = "prefix must be 1-1024 characters."
  }
}
variable "error_output_prefix" {
  type        = string
  default     = "err/"
  description = "Key prefix for records Firehose could not deliver, as the _monolithic template had it"

  validation {
    condition     = length(var.error_output_prefix) > 0 && length(var.error_output_prefix) <= 1024
    error_message = "error_output_prefix must be 1-1024 characters."
  }
}
variable "compression_format" {
  type        = string
  default     = "GZIP"
  description = "Compression applied to delivered objects, as the _monolithic template had it. CloudWatch Logs already gzips what it sends to a subscription, so the objects end up compressed twice - zcat twice to read them"

  validation {
    condition     = contains(["UNCOMPRESSED", "GZIP", "ZIP", "Snappy", "HADOOP_SNAPPY"], var.compression_format)
    error_message = "compression_format must be one of UNCOMPRESSED, GZIP, ZIP, Snappy or HADOOP_SNAPPY."
  }
}
variable "buffering_interval_seconds" {
  type        = number
  default     = 300
  description = "Seconds Firehose buffers before writing to S3. 300 is Firehose's default and what the _monolithic template got by not setting it; lower it to watch objects arrive sooner"

  validation {
    condition     = var.buffering_interval_seconds >= 0 && var.buffering_interval_seconds <= 900
    error_message = "buffering_interval_seconds must be between 0 and 900."
  }
}
variable "buffering_size_mb" {
  type        = number
  default     = 5
  description = "Megabytes Firehose buffers before writing to S3, whichever of size and interval comes first. 5 is Firehose's default"

  validation {
    condition     = var.buffering_size_mb >= 1 && var.buffering_size_mb <= 128
    error_message = "buffering_size_mb must be between 1 and 128."
  }
}
variable "kms_key_rotation_period_in_days" {
  type        = number
  default     = 90
  description = "Days between automatic rotations of the stream's KMS key, as the _monolithic template had it"

  validation {
    condition     = var.kms_key_rotation_period_in_days >= 90 && var.kms_key_rotation_period_in_days <= 2560
    error_message = "kms_key_rotation_period_in_days must be between 90 and 2560."
  }
}
variable "kms_key_deletion_window_in_days" {
  type        = number
  default     = 7
  description = "Days a destroyed KMS key waits before it is deleted, as the _monolithic template had it. Seven is the minimum"

  validation {
    condition     = var.kms_key_deletion_window_in_days >= 7 && var.kms_key_deletion_window_in_days <= 30
    error_message = "kms_key_deletion_window_in_days must be between 7 and 30."
  }
}
