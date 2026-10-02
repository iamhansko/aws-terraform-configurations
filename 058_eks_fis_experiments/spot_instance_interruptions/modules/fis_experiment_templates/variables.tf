variable "role_name" {
  type        = string
  default     = null
  description = "Optional fixed name for the experiment role. Null generates one from role_name_prefix, which is what lets this project be deployed twice in one account - the _monolithic template fixed it to \"aws-fis-itn\", and a second deployment fails on EntityAlreadyExists"

  validation {
    condition     = var.role_name == null || can(regex("^[a-zA-Z0-9+=,.@_-]{1,64}$", var.role_name))
    error_message = "role_name must be 1-64 characters of the set IAM accepts for a role name, or null."
  }
}
variable "role_name_prefix" {
  type        = string
  default     = "fis-experiment-"
  description = "Prefix for the generated role name when role_name is null"

  validation {
    condition     = can(regex("^[a-zA-Z0-9+=,.@_-]{1,32}$", var.role_name_prefix))
    error_message = "role_name_prefix must be 1-32 characters of the set IAM accepts for a role name."
  }
}
variable "managed_policy_arns" {
  type        = list(string)
  default     = ["arn:aws:iam::aws:policy/service-role/AWSFaultInjectionSimulatorEC2Access"]
  description = "Managed policies the experiment role assumes to act on its targets. The EC2 access policy is what lets FIS stop instances and send spot interruption signals, which is the whole extent of what the experiments here do. The _monolithic template also attached an inline policy granting fis:* on *, which an experiment role does not need at all: it acts on the target service, not on FIS - the caller that starts an experiment needs FIS permissions, and that is a different principal"

  validation {
    condition     = alltrue([for arn in var.managed_policy_arns : can(regex("^arn:aws:iam::", arn))])
    error_message = "managed_policy_arns must contain valid IAM policy ARNs."
  }
}
variable "stop_instance_experiment" {
  type = object({
    name_tag       = string
    selection_mode = optional(string, "COUNT(1)")
    description    = optional(string, "Stop one on-demand instance outright, with no interruption warning")
  })
  default     = null
  description = "Enables the stop-instances experiment, targeting instances carrying Name=<name_tag>. Null leaves it out. This is the harsher of the two actions: EC2 issues no warning for an instance it is asked to stop, so the only signal Karpenter gets is the instance state change event - which is why that EventBridge rule is not optional in this project"

  validation {
    condition     = var.stop_instance_experiment == null || length(var.stop_instance_experiment.name_tag) > 0
    error_message = "stop_instance_experiment.name_tag must not be empty; it is how FIS finds the instances to act on."
  }
  validation {
    condition     = var.stop_instance_experiment == null || can(regex("^(ALL|COUNT\\([0-9]+\\)|PERCENT\\([0-9]{1,3}\\))$", var.stop_instance_experiment.selection_mode))
    error_message = "stop_instance_experiment.selection_mode must be ALL, COUNT(n) or PERCENT(n)."
  }
}
variable "spot_interruption_experiment" {
  type = object({
    name_tag                     = string
    selection_mode               = optional(string, "COUNT(1)")
    duration_before_interruption = optional(string, "PT900S")
    description                  = optional(string, "Send a spot interruption warning to one spot instance")
  })
  default     = null
  description = "Enables the spot interruption experiment, targeting spot instances carrying Name=<name_tag>. Null leaves it out. Unlike stopping an instance this produces the real two-minute warning, so it is what exercises Karpenter's interruption queue end to end"

  validation {
    condition     = var.spot_interruption_experiment == null || length(var.spot_interruption_experiment.name_tag) > 0
    error_message = "spot_interruption_experiment.name_tag must not be empty; it is how FIS finds the instances to act on."
  }
  validation {
    condition     = var.spot_interruption_experiment == null || can(regex("^(ALL|COUNT\\([0-9]+\\)|PERCENT\\([0-9]{1,3}\\))$", var.spot_interruption_experiment.selection_mode))
    error_message = "spot_interruption_experiment.selection_mode must be ALL, COUNT(n) or PERCENT(n)."
  }
  validation {
    condition     = var.spot_interruption_experiment == null || can(regex("^PT([0-9]+M)?([0-9]+S)?$", var.spot_interruption_experiment.duration_before_interruption))
    error_message = "spot_interruption_experiment.duration_before_interruption must be an ISO 8601 duration of minutes and seconds, e.g. PT900S. FIS accepts between PT2M and PT1H, and the value is how long after the warning the instance is actually reclaimed - not how long until the warning is sent."
  }
}
variable "empty_target_resolution_mode" {
  type        = string
  default     = "fail"
  description = "What FIS does when a target tag matches no instance. fail as the _monolithic template had it, and worth keeping: skip would let an experiment report success against nothing at all, which is indistinguishable from a system that survived the fault. This is the one setting that makes a mis-tagged target visible"

  validation {
    condition     = contains(["fail", "skip"], var.empty_target_resolution_mode)
    error_message = "empty_target_resolution_mode must be either fail or skip."
  }
}
variable "log_group_arn" {
  type        = string
  default     = null
  description = "Optional CloudWatch log group the experiment delivers its own log to. Null skips it, which is what the _monolithic template did - an experiment then reports only its final state, and which instance it actually resolved to is recorded nowhere. When set, the module also grants the role the four log-delivery actions FIS needs; they are not write permissions on the group, and without them the experiment runs and simply produces no log"

  validation {
    condition     = var.log_group_arn == null || can(regex("^arn:aws:logs:", var.log_group_arn))
    error_message = "log_group_arn must be a CloudWatch log group ARN, or null."
  }
  validation {
    # FIS requires the :* suffix, and the only thing that reports its absence is the API at apply
    # time - after the templates' IAM role and every other resource already exist (rules.md B-1).
    # The caller builds this from aws_cloudwatch_log_group.arn, whose value has included the suffix
    # in some provider versions and not others, so the mistake is easy to make in either direction.
    #
    # $${} so the example renders literally rather than being interpolated here.
    condition     = var.log_group_arn == null || endswith(var.log_group_arn, ":*")
    error_message = "log_group_arn must end with \":*\". FIS rejects a log group ARN without it, with: invalid value for log_configuration.0.cloudwatch_logs_configuration.0.log_group_arn (ARN must end with `:*`). Build it as $${trimsuffix(aws_cloudwatch_log_group.x.arn, \":*\")}:* so it is correct whichever form the provider returns."
  }
}
