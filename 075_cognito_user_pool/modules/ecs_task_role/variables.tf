variable "name_prefix" {
  type        = string
  description = "Prefix for the generated role name"

  validation {
    condition     = can(regex("^[a-zA-Z0-9+=,.@_-]{1,38}$", var.name_prefix))
    error_message = "name_prefix must be 1-38 characters from the set IAM accepts for a role name."
  }
}
variable "dynamodb_table_arns" {
  type        = list(string)
  description = "Tables the tasks may read and write"

  validation {
    condition     = length(var.dynamodb_table_arns) > 0 && alltrue([for arn in var.dynamodb_table_arns : can(regex("^arn:aws[a-zA-Z-]*:dynamodb:", arn))])
    error_message = "dynamodb_table_arns must contain DynamoDB table ARNs."
  }
}
variable "user_pool_arn" {
  type        = string
  description = "User pool the server signs players up and in through"

  validation {
    condition     = can(regex("^arn:aws[a-zA-Z-]*:cognito-idp:", var.user_pool_arn))
    error_message = "user_pool_arn must be a Cognito user pool ARN."
  }
}
variable "image_bucket_arn" {
  type        = string
  description = "Bucket the item image service writes generated images to"

  validation {
    condition     = can(regex("^arn:aws[a-zA-Z-]*:s3:::[a-z0-9.-]+$", var.image_bucket_arn))
    error_message = "image_bucket_arn must be an S3 bucket ARN."
  }
}
