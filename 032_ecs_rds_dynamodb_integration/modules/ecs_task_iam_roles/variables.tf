variable "dynamodb_table_arns" {
  type        = list(string)
  default     = []
  description = "Table ARNs - and index ARN patterns - the task role may read and write. This replaces AdministratorAccess on the task role, which the _monolithic template attached (rules.md A-5). Empty writes no policy at all, which is the correct configuration for a caller whose applications make no AWS calls"
  validation {
    condition     = alltrue([for arn in var.dynamodb_table_arns : can(regex("^arn:aws[a-z-]*:dynamodb:", arn))])
    error_message = "dynamodb_table_arns must contain DynamoDB ARNs (e.g. arn:aws:dynamodb:ap-northeast-2:123456789012:table/appdev-dynamo-table)."
  }
}
variable "secret_arns" {
  type        = list(string)
  default     = []
  description = "Secret ARNs the task execution role may read, so it can inject the database password into the user container before it starts. One here, which is what replaces CloudWatchFullAccessV2 (rules.md A-5). Empty writes no policy, for a caller with no secrets in its task definitions"
  validation {
    condition     = alltrue([for arn in var.secret_arns : can(regex("^arn:aws[a-z-]*:secretsmanager:", arn))])
    error_message = "secret_arns must contain Secrets Manager secret ARNs."
  }
}
variable "execution_policy_arns" {
  type        = list(string)
  default     = ["arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"]
  description = "Managed policy ARNs on the task execution role. AmazonECSTaskExecutionRolePolicy only: it is the AWS service-role policy for this role and covers the ECR token, the layer pulls and the log streams. The template's second attachment, CloudWatchFullAccessV2, is replaced by a scoped inline policy (rules.md A-5)"
  validation {
    condition     = length(var.execution_policy_arns) > 0
    error_message = "execution_policy_arns must contain at least one policy. Without the ECR and logs permissions in AmazonECSTaskExecutionRolePolicy every task stops with CannotPullContainerError."
  }
  validation {
    condition     = alltrue([for arn in var.execution_policy_arns : can(regex("^arn:aws:iam::", arn))])
    error_message = "execution_policy_arns must contain valid IAM policy ARNs."
  }
}
variable "additional_task_policy_arns" {
  type        = list(string)
  default     = []
  description = "Extra managed policy ARNs on the task role, on top of the scoped DynamoDB policy this module writes. Empty by default: only one of the three applications calls an AWS API, and a variable whose default is a broad policy does not get narrowed later (rules.md A-5)"
  validation {
    condition     = alltrue([for arn in var.additional_task_policy_arns : can(regex("^arn:aws:iam::", arn))])
    error_message = "additional_task_policy_arns must contain valid IAM policy ARNs."
  }
}
