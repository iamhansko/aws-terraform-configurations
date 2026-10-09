variable "task_role_name_prefix" {
  type        = string
  description = "Prefix for the generated task role name. A prefix rather than the template's fixed EcsTaskIamRole-<uuid slice>: the uuid stood in for AWS::StackId, and name_prefix is the provider's own way of getting the same uniqueness"

  validation {
    condition     = can(regex("^[a-zA-Z0-9+=,.@_-]{1,38}$", var.task_role_name_prefix))
    error_message = "task_role_name_prefix must be 1-38 characters from the set IAM accepts in a role name, leaving room for the generated suffix inside the 64 character limit."
  }
}
variable "execution_role_name_prefix" {
  type        = string
  description = "Prefix for the generated task execution role name"

  validation {
    condition     = can(regex("^[a-zA-Z0-9+=,.@_-]{1,38}$", var.execution_role_name_prefix))
    error_message = "execution_role_name_prefix must be 1-38 characters from the set IAM accepts in a role name, leaving room for the generated suffix inside the 64 character limit."
  }
}
variable "secret_arns" {
  type        = list(string)
  description = "Secret ARNs the execution role may read. One here - the database credential document both task definitions pull DB_URL, DB_USER and DB_PASSWD from. This replaces SecretsManagerReadWrite, which granted read and write on every secret in the account (rules.md A-5)"

  validation {
    condition     = length(var.secret_arns) > 0
    error_message = "secret_arns must contain at least one ARN: with an empty list the policy statement has no resource and IAM rejects the whole policy with MalformedPolicyDocument."
  }
  validation {
    condition     = alltrue([for arn in var.secret_arns : can(regex("^arn:aws[a-z-]*:secretsmanager:", arn))])
    error_message = "secret_arns must contain Secrets Manager secret ARNs."
  }
}
variable "kms_key_arn" {
  type        = string
  description = "Key the credential secret is encrypted with. The execution role needs kms:Decrypt on it, and without that the GetSecretValue passes IAM and fails at KMS - with the task's stopped reason naming the secret rather than the key"

  validation {
    condition     = can(regex("^arn:aws[a-z-]*:kms:", var.kms_key_arn))
    error_message = "kms_key_arn must be a KMS key ARN."
  }
}
variable "log_group_arn_patterns" {
  type        = list(string)
  description = <<-DESC
    Log group ARNs, possibly with wildcards, that the FireLens sidecar may write to and the
    execution role may create.

    Patterns rather than the real ARNs on purpose. The log groups belong to the application
    stacks, and a stack's task definition names these two roles - so taking the ARNs from the
    stack module would make each stack depend on the roles and the roles depend on every stack,
    which is a cycle. The root builds these from the same project name the log group names are
    built from, so the two still come from one value (rules.md B-5).

    Include both the group ARN and the group ARN with a ":*" suffix: a log group ARN alone does
    not authorise CreateLogStream or PutLogEvents inside it.
  DESC

  validation {
    condition     = length(var.log_group_arn_patterns) > 0
    error_message = "log_group_arn_patterns must contain at least one pattern: an empty resource list makes IAM reject the policy with MalformedPolicyDocument."
  }
  validation {
    condition     = alltrue([for arn in var.log_group_arn_patterns : can(regex("^arn:aws[a-z-]*:logs:", arn))])
    error_message = "log_group_arn_patterns must contain CloudWatch Logs ARNs (e.g. arn:aws:logs:ap-northeast-2:123456789012:log-group:/ws25/logs/*)."
  }
}
variable "execution_policy_arns" {
  type        = list(string)
  description = "Managed policy ARNs on the task execution role. AmazonECSTaskExecutionRolePolicy only: it is the AWS service-role policy for this role, and the other two the _monolithic template attached are replaced by a scoped inline policy (rules.md A-5)"

  validation {
    condition     = length(var.execution_policy_arns) > 0
    error_message = "execution_policy_arns must contain at least one policy: without the ECR and logs permissions in AmazonECSTaskExecutionRolePolicy every task stops with CannotPullContainerError."
  }
  validation {
    condition     = alltrue([for arn in var.execution_policy_arns : can(regex("^arn:aws:iam::", arn))])
    error_message = "execution_policy_arns must contain valid IAM policy ARNs."
  }
}
variable "additional_task_policy_arns" {
  type        = list(string)
  default     = []
  description = "Extra managed policy ARNs on the task role, on top of the FireLens logs policy this module writes. Empty by default: the application containers make no AWS calls, and a variable whose default is a broad policy does not get narrowed later (rules.md A-5)"

  validation {
    condition     = alltrue([for arn in var.additional_task_policy_arns : can(regex("^arn:aws:iam::", arn))])
    error_message = "additional_task_policy_arns must contain valid IAM policy ARNs."
  }
}
