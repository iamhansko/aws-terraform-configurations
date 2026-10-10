variable "name" {
  type        = string
  description = "Name of the topic. The _monolithic template declared a bare aws_sns_topic with no arguments, so the name was generated and appeared nowhere"

  validation {
    condition     = can(regex("^[a-zA-Z0-9_-]{1,256}$", var.name))
    error_message = "name must be 1-256 characters of letters, digits, hyphens and underscores - SNS's own limit for a standard topic."
  }
}
variable "display_name" {
  type        = string
  default     = null
  description = "Display name, which is what appears as the sender on an email subscription. Null leaves it unset, and an email from an unset display name arrives from the topic's raw name"

  validation {
    condition     = var.display_name == null || length(var.display_name) <= 100
    error_message = "display_name must be 100 characters or fewer, or null."
  }
}
variable "email_subscriptions" {
  type        = list(string)
  default     = []
  description = <<-DESC
    Addresses subscribed to the topic. Empty by default, which is the _monolithic template's behaviour and
    worth being explicit about: a publish to a topic with no subscriptions succeeds and the message goes
    nowhere. Both notification states in the state machine therefore reported success while notifying nobody.

    An email subscription is created in a pending state and only starts delivering once the address owner
    clicks the confirmation link, which Terraform cannot do - so this stays empty by default rather than
    creating something that looks finished and is not.
  DESC

  validation {
    condition     = alltrue([for address in var.email_subscriptions : can(regex("^[^@\\s]+@[^@\\s]+\\.[^@\\s]+$", address))])
    error_message = "email_subscriptions must contain email addresses."
  }
}
variable "publisher_role_arns" {
  type        = list(string)
  default     = []
  description = "Roles allowed to publish through a topic policy. Empty by default: the state machine's own IAM policy grants sns:Publish, which is enough for a same-account publish. A topic policy is what a cross-account publisher would need"

  validation {
    condition     = alltrue([for arn in var.publisher_role_arns : can(regex("^arn:aws:iam::", arn))])
    error_message = "publisher_role_arns must contain IAM ARNs."
  }
}
