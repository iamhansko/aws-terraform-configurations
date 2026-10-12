variable "name" {
  type        = string
  default     = "CloudFormationIamRole"
  description = "Name of the service role, as the _monolithic template had it. Fixed, so a second copy of this root in the same account fails with EntityAlreadyExists"

  validation {
    condition     = can(regex("^[a-zA-Z0-9+=,.@_-]{1,64}$", var.name))
    error_message = "name must be 1-64 characters from the set IAM accepts for a role name."
  }
}
variable "policy_arns" {
  type        = list(string)
  default     = ["arn:aws:iam::aws:policy/AdministratorAccess"]
  description = <<-DESC
    Managed policies attached to the service role. AdministratorAccess, as the _monolithic template attached it
    explicitly.

    It stays the default because a CloudFormation service role has to be able to create whatever the
    template contains, and this role's template is supplied from another account - this root does not get to
    see it. The template here creates one VPC, so AmazonVPCFullAccess would be enough today; that is the
    narrower choice, and it breaks the moment the bucket account changes the template.
  DESC

  validation {
    condition     = length(var.policy_arns) > 0 && alltrue([for arn in var.policy_arns : can(regex("^arn:aws:iam::(aws|[0-9]{12}):policy/", arn))])
    error_message = "policy_arns must contain at least one valid IAM managed policy ARN."
  }
}
