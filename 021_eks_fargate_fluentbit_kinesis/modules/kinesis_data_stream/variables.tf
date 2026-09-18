variable "name" {
  type        = string
  description = "Name of the Kinesis data stream. Fluent Bit names it in the OUTPUT block's stream field, so this value reaches the cluster as configuration"

  validation {
    condition     = can(regex("^[a-zA-Z0-9_.-]{1,128}$", var.name))
    error_message = "name must be 1-128 characters of letters, digits, underscores, dots or hyphens - the set Kinesis accepts for a stream name."
  }
}
variable "stream_mode" {
  type        = string
  default     = "ON_DEMAND"
  description = "Capacity mode. ON_DEMAND scales shards automatically and bills per record, which suits a demo whose log volume is a few records per second; PROVISIONED needs shard_count chosen up front and bills for it whether anything is logging or not"

  validation {
    condition     = contains(["ON_DEMAND", "PROVISIONED"], var.stream_mode)
    error_message = "stream_mode must be either ON_DEMAND or PROVISIONED."
  }
}
variable "shard_count" {
  type        = number
  default     = 1
  description = "Number of shards, applied only when stream_mode is PROVISIONED. Kinesis rejects a shard count on an ON_DEMAND stream, so the module drops it in that mode rather than letting the apply fail"

  validation {
    condition     = var.shard_count >= 1
    error_message = "shard_count must be at least 1."
  }
}
variable "retention_period_hours" {
  type        = number
  default     = 24
  description = "How long records stay readable in the stream. 24 hours is the Kinesis minimum and the default, which is enough for a demo that reads records right after they are written"

  validation {
    condition     = var.retention_period_hours >= 24 && var.retention_period_hours <= 8760
    error_message = "retention_period_hours must be between 24 and 8760 (365 days), the range Kinesis accepts."
  }
}
variable "encryption_type" {
  type        = string
  default     = "KMS"
  description = "Server-side encryption. KMS with the AWS-managed key (alias/aws/kinesis) by default, which costs nothing extra and needs no key policy work; NONE leaves records unencrypted at rest"

  validation {
    condition     = contains(["KMS", "NONE"], var.encryption_type)
    error_message = "encryption_type must be either KMS or NONE."
  }
}
variable "kms_key_id" {
  type        = string
  default     = "alias/aws/kinesis"
  description = "KMS key used when encryption_type is KMS. The AWS-managed Kinesis key by default. A customer-managed key needs a key policy that lets the Fargate pod execution role use it, otherwise Fluent Bit's PutRecords fails with AccessDenied and the logs vanish with no error in the cluster"

  validation {
    condition     = length(var.kms_key_id) > 0
    error_message = "kms_key_id must not be empty."
  }
}
