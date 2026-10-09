variable "administration_role_name" {
  type        = string
  default     = "AWSCloudFormationStackSetAdministrationRole"
  description = <<-DESC
    Name of the role CloudFormation assumes to drive the StackSet.

    Fixed rather than generated, and this is one of the cases where that is right: it is the name AWS's own
    documentation and setup templates use, so an account that already has a self-managed StackSet has this
    role and this module would collide with it. The cost is the usual one - the project cannot be applied
    twice into one account without changing the value (rules.md I-2 has the same tradeoff for a different
    reason).
  DESC

  validation {
    condition     = can(regex("^[a-zA-Z0-9+=,.@_-]{1,64}$", var.administration_role_name))
    error_message = "administration_role_name must be 1-64 characters from the set IAM accepts for a role name."
  }
}
variable "execution_role_name" {
  type        = string
  default     = "AWSCloudFormationStackSetExecutionRole"
  description = "Name of the role the administration role assumes inside each target account. Fixed for the same reason, and with one more constraint: a StackSet names this role by name rather than by ARN, so every target account has to have a role called exactly this"

  validation {
    condition     = can(regex("^[a-zA-Z0-9+=,.@_-]{1,64}$", var.execution_role_name))
    error_message = "execution_role_name must be 1-64 characters from the set IAM accepts for a role name."
  }
}
variable "trusted_administrator_account_ids" {
  type        = list(string)
  description = "Accounts whose administration role may assume the execution role created here. For a single-account StackSet this is the account itself"

  validation {
    condition     = length(var.trusted_administrator_account_ids) > 0 && alltrue([for id in var.trusted_administrator_account_ids : can(regex("^[0-9]{12}$", id))])
    error_message = "trusted_administrator_account_ids must be a non-empty list of 12-digit AWS account IDs."
  }
}
variable "execution_role_policy_arns" {
  type        = list(string)
  default     = ["arn:aws:iam::aws:policy/AdministratorAccess"]
  description = <<-DESC
    Managed policies attached to the execution role, as the _monolithic template had them - which is to say
    AdministratorAccess.

    That is what AWS's own self-managed StackSet setup template attaches, and the reason is real: the
    execution role has to be able to create whatever any template deployed through this StackSet contains,
    and a StackSet does not know in advance what that is. It is still administrator in every target account.

    A narrower alternative for this project specifically is execution_role_inline_policy_statements below:
    the template here creates one IAM managed policy and nothing else.
  DESC

  validation {
    condition     = alltrue([for arn in var.execution_role_policy_arns : can(regex("^arn:aws:iam::", arn))])
    error_message = "execution_role_policy_arns must contain valid IAM policy ARNs."
  }
}
variable "execution_role_inline_policy_statements" {
  type        = list(any)
  default     = []
  description = "Statements added to the execution role as an inline policy, for narrowing it below the managed policies above. Empty by default, which leaves the original's behaviour. Passing statements here does not remove the managed policies - set execution_role_policy_arns to [] for that"
}
variable "administration_role_description" {
  type        = string
  default     = "Assumed by CloudFormation to drive a self-managed StackSet"
  description = "Description on the administration role. Unlike a security group description this is editable in place, so it costs nothing"

  validation {
    condition     = length(var.administration_role_description) <= 1000
    error_message = "administration_role_description must be 1000 characters or fewer - IAM's own limit."
  }
}
