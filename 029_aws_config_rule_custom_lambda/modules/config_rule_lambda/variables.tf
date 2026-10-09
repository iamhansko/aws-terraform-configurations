variable "account_id" {
  type        = string
  description = "Account the rule and function live in, used for the invoke permission's source account and source ARN. Injected rather than read here with data.aws_caller_identity, because this module carries depends_on and a data source inside it would be deferred to apply (rules.md B-6, D-6)"

  validation {
    condition     = can(regex("^[0-9]{12}$", var.account_id))
    error_message = "account_id must be a 12-digit AWS account ID."
  }
}
variable "region" {
  type        = string
  description = "Region the rule lives in, for the invoke permission's source ARN and the verification commands in the outputs. Injected for the same reason as account_id"

  validation {
    condition     = can(regex("^[a-z]{2}(-[a-z]+)+-[0-9]$", var.region))
    error_message = "region must look like an AWS region (e.g. ap-northeast-2)."
  }
}
variable "rule_name" {
  type        = string
  description = "Name of the Config rule"

  validation {
    condition     = can(regex("^[a-zA-Z0-9_-]{1,128}$", var.rule_name))
    error_message = "rule_name must be 1-128 characters of letters, digits, hyphens and underscores."
  }
}
variable "rule_resource_types" {
  type        = list(string)
  default     = ["AWS::EC2::Instance"]
  description = "Resource types the rule's scope restricts evaluation to. The handler checks the type again and returns early on a mismatch, so this list is the cheap half of a constraint that is enforced twice - see the caller's variable of the same name for what widening it actually does"

  validation {
    condition     = length(var.rule_resource_types) > 0
    error_message = "rule_resource_types must not be empty. An empty scope makes the rule evaluate every recorded resource type in the account, which for this handler means an invocation per configuration item that reports nothing."
  }
  validation {
    condition     = alltrue([for type in var.rule_resource_types : can(regex("^AWS::[A-Za-z0-9]+::[A-Za-z0-9]+$", type))])
    error_message = "rule_resource_types must contain AWS::Service::Resource type names (e.g. AWS::EC2::Instance)."
  }
}
variable "rule_message_types" {
  type = list(string)
  default = [
    "ConfigurationItemChangeNotification",
    "OversizedConfigurationItemChangeNotification",
  ]
  description = <<-DESC
    Which notifications Config sends to the function, as the _monolithic template had them.

    Both are change-triggered, which is what makes this rule evaluate on a change rather than on a
    schedule - and why there is a command in the outputs to force an evaluation, since nothing
    happens until something changes.

    The handler only really implements the first. An oversized notification carries a
    configurationItemSummary and an S3 pointer instead of a configurationItem, so
    invoking_event.get('configurationItem', {}) returns {}, resourceType is None, and the handler
    returns before calling put_evaluations. No error, no evaluation. It stays in the list because the
    original had it and because an EC2 instance configuration item is nowhere near the 64 KB
    threshold that triggers it - this is dormant rather than broken, and removing it would hide a gap
    that is worth knowing about if the rule is ever pointed at a larger resource type.
  DESC

  validation {
    condition = alltrue([for type in var.rule_message_types : contains([
      "ConfigurationItemChangeNotification",
      "OversizedConfigurationItemChangeNotification",
      "ScheduledNotification",
    ], type)])
    error_message = "rule_message_types must contain only ConfigurationItemChangeNotification, OversizedConfigurationItemChangeNotification or ScheduledNotification."
  }
  validation {
    condition     = !contains(var.rule_message_types, "ScheduledNotification")
    error_message = "ScheduledNotification is not supported by this handler. It reads event['invokingEvent'].configurationItem, which a scheduled notification does not contain, so every scheduled run would raise a KeyError visible only in the function's log. A periodic version has to list resources itself; use start-config-rules-evaluation to re-run the change-triggered rule instead."
  }
}
variable "function_name" {
  type        = string
  description = "Name of the function backing the rule"

  validation {
    condition     = can(regex("^[a-zA-Z0-9_-]{1,64}$", var.function_name))
    error_message = "function_name must be 1-64 characters of letters, digits, hyphens and underscores."
  }
}
variable "runtime" {
  type        = string
  default     = "python3.13"
  description = "Lambda runtime. Must stay a Python runtime: the package is one .py file and boto3 is on the path only because the Python runtimes bundle it"

  validation {
    condition     = can(regex("^python3\\.[0-9]+$", var.runtime))
    error_message = "runtime must be a python3.x runtime, because the handler is Python and relies on the boto3 those runtimes provide."
  }
}
variable "handler" {
  type        = string
  default     = "index.lambda_handler"
  description = "Entry point as module.function. A mismatch with the Python is not a plan error: Config invokes the function, Lambda answers Runtime.HandlerNotFound, and the rule sits at \"No results available\""

  validation {
    condition     = can(regex("^[A-Za-z0-9_.-]+\\.[A-Za-z0-9_]+$", var.handler))
    error_message = "handler must be of the form module.function (e.g. index.lambda_handler)."
  }
}
variable "timeout_seconds" {
  type        = number
  default     = 60
  description = "How long the function may run. A timeout is reported to Config as nothing at all - the invocation dies before put_evaluations - so the resource stays unevaluated rather than failing"

  validation {
    condition     = var.timeout_seconds >= 1 && var.timeout_seconds <= 900
    error_message = "timeout_seconds must be between 1 and 900, the range Lambda accepts."
  }
}
variable "filename" {
  type        = string
  description = "Path to the deployment package, produced by the caller's archive_file (rules.md B-6, and D-6 for why it is not built here)"

  validation {
    condition     = can(regex("\\.zip$", var.filename))
    error_message = "filename must be the path to a .zip deployment package."
  }
}
variable "source_code_hash" {
  type        = string
  description = "Base64 SHA-256 of that package, from the same archive_file. Without it Lambda keeps running the code it already has after index.py changes, and plan reports no difference"

  validation {
    condition     = can(regex("^[A-Za-z0-9+/]{43}=$", var.source_code_hash))
    error_message = "source_code_hash must be a base64-encoded SHA-256 digest, which is what archive_file's output_base64sha256 produces."
  }
}
variable "log_group_name" {
  type        = string
  description = "CloudWatch log group the function writes to. This log is where a rule that never evaluates leaves its only evidence, so it is named explicitly rather than left to the /aws/lambda/<name> default"

  validation {
    condition     = can(regex("^[a-zA-Z0-9_./#-]{1,512}$", var.log_group_name))
    error_message = "log_group_name must be 1-512 characters from the set CloudWatch Logs accepts (letters, digits and _ . / # -)."
  }
}
variable "create_log_group" {
  type        = bool
  default     = true
  description = "Whether this module creates the log group. False leaves the function to create it on first invocation, which is what the _monolithic template relied on - and which means the group survives destroy with no expiry"
}
variable "log_retention_days" {
  type        = number
  default     = 14
  description = "Retention on that group. Ignored when create_log_group is false, because a group the function creates for itself never expires"

  validation {
    condition     = contains([1, 3, 5, 7, 14, 30, 60, 90, 120, 150, 180, 365, 400, 545, 731, 1096, 1827, 2192, 2557, 2922, 3288, 3653], var.log_retention_days)
    error_message = "log_retention_days must be one of the values CloudWatch Logs accepts (1, 3, 5, 7, 14, 30, 60, 90, 120, 150, 180, 365, 400, 545, 731, 1096, 1827, 2192, 2557, 2922, 3288, 3653)."
  }
}
variable "role_name_prefix" {
  type        = string
  default     = "config-rule-lambda-"
  description = "Prefix for the generated name of the function's execution role. The _monolithic template left the whole name to the provider"

  validation {
    condition     = can(regex("^[\\w+=,.@-]{1,32}$", var.role_name_prefix))
    error_message = "role_name_prefix must be 1-32 characters from the set IAM accepts for role names (letters, digits and _+=,.@-), leaving room for the generated suffix inside the 64 character limit."
  }
}
variable "inline_policy_name" {
  type        = string
  default     = "AttachOnly-AmazonS3ReadOnlyAccess"
  description = "Name of the function role's inline policy, as the _monolithic template had it. An odd name for a policy that grants IAM reads and writes plus config:PutEvaluations - it describes the rule the handler enforces rather than the permissions it holds - kept because renaming it replaces the policy and tells a reader nothing new"

  validation {
    condition     = can(regex("^[\\w+=,.@-]{1,128}$", var.inline_policy_name))
    error_message = "inline_policy_name must be 1-128 characters from the set IAM accepts for policy names (letters, digits and _+=,.@-)."
  }
}
variable "evaluation_policy_actions" {
  type = list(string)
  default = [
    "iam:GetInstanceProfile",
    "iam:ListAttachedRolePolicies",
    "config:PutEvaluations",
  ]
  description = "What the handler needs to read an instance profile and report a verdict, from the _monolithic template's inline policy. These three are the whole of the evaluation path: resolve the profile named in the configuration item, list its role's attached policies, report the result"

  validation {
    condition     = contains(var.evaluation_policy_actions, "config:PutEvaluations")
    error_message = "evaluation_policy_actions must include config:PutEvaluations. Without it the handler runs, decides a verdict and then raises AccessDenied inside boto3 - the rule stays at \"No results available\" and the only record is a stack trace in the function's log."
  }
  validation {
    condition     = alltrue([for action in var.evaluation_policy_actions : can(regex("^[a-z0-9]+:[A-Za-z0-9*]+$", action))])
    error_message = "evaluation_policy_actions must be service:Action strings."
  }
}
variable "remediation_policy_actions" {
  type = list(string)
  default = [
    "iam:AttachRolePolicy",
    "iam:DetachRolePolicy",
  ]
  description = <<-DESC
    What the handler needs to change IAM, also from the _monolithic template's inline policy.

    Kept separate from evaluation_policy_actions because these two write actions are the surprising
    part of this project: the handler does not only evaluate. On finding a non-compliant profile it
    detaches every policy that is not AmazonS3ReadOnlyAccess, attaches AmazonS3ReadOnlyAccess, and
    then reports the resource compliant. A Config rule would normally be read-only and leave fixing
    to a remediation configuration.

    Setting this to [] makes the rule read-only. That is a real option and it changes the demo: the
    non-compliant fixture then stays non-compliant and can be looked at more than once, but the
    handler raises AccessDenied inside its remediation branch - which it catches, turning the verdict
    into NON_COMPLIANT with an "Error occurred" annotation rather than a clean report.
  DESC

  validation {
    condition     = alltrue([for action in var.remediation_policy_actions : can(regex("^iam:[A-Za-z0-9*]+$", action))])
    error_message = "remediation_policy_actions must be iam: actions."
  }
}
