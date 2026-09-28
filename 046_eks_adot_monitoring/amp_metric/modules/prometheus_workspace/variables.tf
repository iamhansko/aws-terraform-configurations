variable "alias" {
  type        = string
  description = "Human-readable name for the workspace. Not its identity - AMP assigns a ws-<uuid> ID that everything actually references - but it is what the console lists, and it is used here to name the log groups so two deployments in one account do not collide"

  validation {
    condition     = can(regex("^[a-zA-Z0-9][a-zA-Z0-9-_.]{0,99}$", var.alias))
    error_message = "alias must start with a letter or digit and contain only letters, digits, hyphens, underscores and dots (100 characters or fewer)."
  }
}
variable "enable_rule_logging" {
  type        = bool
  default     = true
  description = "Whether AMP writes rule evaluation logs to CloudWatch. These are the errors from recording and alerting rules - a rule that fails to evaluate is otherwise invisible, since the workspace simply has no data for it"
}
variable "enable_query_logging" {
  type        = bool
  default     = true
  description = "Whether AMP logs the queries it serves. The _monolithic template created a log group for this and never connected it: the CloudFormation template's QueryLoggingConfiguration was one of the properties cfn2tf could not map, so it was left as a comment - leaving an empty log group and query logging switched off, with nothing to indicate either"
}
variable "query_logging_qsp_threshold" {
  type        = number
  default     = 0
  description = "Minimum queries-samples-processed a query must reach to be logged, as the _monolithic template's unmapped configuration had it. Zero logs every query, which is what a demo wants and a busy workspace does not - the log volume is proportional to query traffic, not to how expensive the queries are"

  validation {
    condition     = var.query_logging_qsp_threshold >= 0
    error_message = "query_logging_qsp_threshold must be zero or greater."
  }
}
variable "log_group_prefix" {
  type        = string
  default     = "/aws/vendedlogs/aps"
  description = "Prefix for the two log groups. /aws/vendedlogs is not cosmetic: CloudWatch Logs treats groups under it as vended logs and lets the publishing service write to them without a log group resource policy. The _monolithic template used /aws/amp, which needs an explicit policy granting aps.amazonaws.com logs:PutLogEvents - and without one the logging configuration is accepted and no log line ever arrives"

  validation {
    condition     = can(regex("^/[a-zA-Z0-9_./#-]{0,400}[^/]$", var.log_group_prefix))
    error_message = "log_group_prefix must be an absolute CloudWatch log group path with no trailing slash."
  }
}
variable "log_retention_days" {
  type        = number
  default     = 7
  description = "How long the rule and query logs are kept. The _monolithic template created both groups with no retention, so they never expire and survive a terraform destroy. Set to 0 to keep events indefinitely"

  validation {
    condition = var.log_retention_days == 0 || contains([
      1, 3, 5, 7, 14, 30, 60, 90, 120, 150, 180, 365, 400, 545, 731, 1096, 1827, 2192, 2557, 2922, 3288, 3653
    ], var.log_retention_days)
    error_message = "log_retention_days must be 0 (never expire) or one of the retention periods CloudWatch Logs accepts: 1, 3, 5, 7, 14, 30, 60, 90, 120, 150, 180, 365, 400, 545, 731, 1096, 1827, 2192, 2557, 2922, 3288, 3653."
  }
}
