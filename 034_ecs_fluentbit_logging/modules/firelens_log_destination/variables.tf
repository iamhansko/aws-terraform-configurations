variable "application_log_group_name" {
  type        = string
  default     = "/logging/cloudwatch"
  description = "Log group Fluent Bit delivers the application's lines to, as the _monolithic template's FireLens options named it. A literal rather than a derived name, which means two copies of this project in one account collide here with ResourceAlreadyExistsException - override it to deploy twice"
  validation {
    condition     = can(regex("^[a-zA-Z0-9_/.#-]{1,512}$", var.application_log_group_name))
    error_message = "application_log_group_name must be 1-512 characters of letters, digits, underscores, hyphens, slashes, dots and hash signs, which is the set CloudWatch Logs accepts for a log group name."
  }
}
variable "log_router_log_group_name" {
  type        = string
  default     = "/fluentbit/cloudwatch"
  description = "Log group the log router's own stdout goes to over the awslogs driver, as the _monolithic template's log configuration named it. Separate from the application group on purpose: when the application group is empty, this one holds the reason"
  validation {
    condition     = can(regex("^[a-zA-Z0-9_/.#-]{1,512}$", var.log_router_log_group_name))
    error_message = "log_router_log_group_name must be 1-512 characters of letters, digits, underscores, hyphens, slashes, dots and hash signs, which is the set CloudWatch Logs accepts for a log group name."
  }
}
variable "retention_in_days" {
  type        = number
  default     = 7
  description = "How long records are kept in both groups. The _monolithic template created neither group, so both would have kept everything forever at full price - a retention is not available as a Fluent Bit option unless the plugin is also allowed logs:PutRetentionPolicy, which is the other reason to create the groups here. Null keeps records indefinitely"
  validation {
    condition     = var.retention_in_days == null || contains([1, 3, 5, 7, 14, 30, 60, 90, 120, 150, 180, 365, 400, 545, 731, 1096, 1827, 2192, 2557, 2922, 3288, 3653], var.retention_in_days)
    error_message = "retention_in_days must be one of the values CloudWatch Logs accepts (1, 3, 5, 7, 14, 30, 60, 90, 120, 150, 180, 365, 400, 545, 731, 1096, 1827, 2192, 2557, 2922, 3288, 3653), or null to keep records forever."
  }
}
variable "auto_create_group" {
  type        = bool
  default     = false
  description = <<-DESC
    Whether the Fluent Bit cloudwatch_logs plugin is told to create the application log group itself.
    False, because this module creates it. One variable decides both the plugin option this module hands
    to the task definition and whether the policy it builds carries logs:CreateLogGroup, so the permission
    and the behaviour cannot drift apart (rules.md B-5).
    The _monolithic template relied on this being true, with no group declared anywhere. That works, and
    the two costs are that the group arrives with no retention and outlives terraform destroy, and that
    CreateLogGroup is an account-level action - it cannot be scoped to the group being created, so
    granting it necessarily widens the task role beyond this project.
  DESC
}
variable "log_stream_prefix" {
  type        = string
  default     = "app-"
  description = "Prefix for the stream names the cloudwatch_logs plugin creates, as the _monolithic template set it. The plugin appends the FireLens tag, so the streams come out as app-<container-name>-firelens-<task-id>"
  validation {
    condition     = can(regex("^[^:*]*$", var.log_stream_prefix))
    error_message = "log_stream_prefix must not contain ':' or '*', which CloudWatch Logs rejects in a stream name."
  }
}
variable "policy_name_prefix" {
  type        = string
  default     = "firelens-log-router-"
  description = "Prefix for the generated name of the log router's IAM policy. A prefix rather than a fixed name, so two copies of this project in one account do not collide with EntityAlreadyExists"
  validation {
    condition     = can(regex("^[a-zA-Z0-9+=,.@_-]{1,96}$", var.policy_name_prefix))
    error_message = "policy_name_prefix must be 1-96 characters of the set IAM accepts for a policy name, leaving room for the generated suffix inside the 128 character limit."
  }
}
