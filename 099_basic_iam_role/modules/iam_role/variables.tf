variable "name_prefix" {
  type        = string
  description = "Prefix for the generated role name. A prefix rather than a fixed name, so this project can be deployed twice in one account - an IAM role name is unique per account, and the _monolithic template sidestepped that only because CloudFormation generated the names for it"

  validation {
    condition     = can(regex("^[a-zA-Z0-9+=,.@_-]{1,38}$", var.name_prefix))
    error_message = "name_prefix must be 1-38 characters from the set IAM accepts for a role name, leaving room for the generated suffix inside the 64 character limit."
  }
}
variable "assume_role_policy_json" {
  type        = string
  description = "The trust policy, as a JSON document. A string rather than an object, because which of the three ways of producing it the caller used is this project's whole subject - the module takes the result and cannot tell them apart (rules.md B-6)"

  validation {
    condition     = can(jsondecode(var.assume_role_policy_json))
    error_message = "assume_role_policy_json must be valid JSON. This catches at plan time what IAM would otherwise reject at apply - a heredoc with a trailing comma, most often."
  }
  validation {
    # A trust policy without a Version is accepted by IAM and silently treated as the 2008 version, which
    # does not support policy variables. Worth failing on rather than inheriting (rules.md B-1).
    condition     = try(jsondecode(var.assume_role_policy_json).Version, null) == "2012-10-17"
    error_message = "assume_role_policy_json must declare \"Version\": \"2012-10-17\". IAM accepts a document without it and treats it as the 2008 version, which does not support policy variables or condition keys added since."
  }
  validation {
    condition     = try(length(jsondecode(var.assume_role_policy_json).Statement), 0) > 0
    error_message = "assume_role_policy_json must contain at least one statement."
  }
}
variable "inline_policy_name" {
  type        = string
  default     = "GetS3Policy"
  description = "Name of the inline policy, as the _monolithic template named it. Inline rather than managed, which is what that template used: a managed policy would be shareable between the three roles, and keeping them inline is what makes each role self-contained"

  validation {
    condition     = can(regex("^[a-zA-Z0-9+=,.@_-]{1,128}$", var.inline_policy_name))
    error_message = "inline_policy_name must be 1-128 characters from the set IAM accepts for a policy name."
  }
}
variable "inline_policy_json" {
  type        = string
  description = "The permissions policy, as a JSON document. Produced by the caller the same way as the trust policy, for the same reason"

  validation {
    condition     = can(jsondecode(var.inline_policy_json))
    error_message = "inline_policy_json must be valid JSON."
  }
  validation {
    condition     = try(jsondecode(var.inline_policy_json).Version, null) == "2012-10-17"
    error_message = "inline_policy_json must declare \"Version\": \"2012-10-17\"."
  }
}
variable "description" {
  type        = string
  default     = null
  description = "Description on the role. Null leaves it unset, as the _monolithic template did. Unlike a security group description this one is editable in place, so it costs nothing to set later"

  validation {
    condition     = var.description == null || length(var.description) <= 1000
    error_message = "description must be 1000 characters or fewer - IAM's own limit - or null."
  }
}
variable "max_session_duration" {
  type        = number
  default     = 3600
  description = "How long a session assumed through this role lasts. One hour, which is IAM's default stated explicitly rather than inherited"

  validation {
    condition     = var.max_session_duration >= 3600 && var.max_session_duration <= 43200
    error_message = "max_session_duration must be between 3600 and 43200 seconds - IAM's own range."
  }
}
