variable "autoscaling_group_names" {
  type        = map(string)
  description = "Auto Scaling group name per caller-chosen label, which also becomes the hook name prefix. A map rather than a list because these names come from a node group created in the same apply and are unknown until then, and for_each needs statically known keys (rules.md B-8)"

  validation {
    condition     = length(var.autoscaling_group_names) > 0
    error_message = "autoscaling_group_names must contain at least one entry; a module creating no hooks is better left out of the configuration."
  }
  validation {
    condition     = alltrue([for label in keys(var.autoscaling_group_names) : can(regex("^[a-zA-Z0-9._-]+$", label))])
    error_message = "autoscaling_group_names keys become part of the hook names and the resource addresses, so each must be letters, digits, dots, underscores or hyphens."
  }
}
variable "create_launching_hooks" {
  type        = bool
  default     = true
  description = "Whether to also create the EC2_INSTANCE_LAUNCHING hooks, as the _monolithic template did. The handler does not act on launching events - this is Auto Scaling guarding itself, so that an instance which never reports healthy is terminated rather than joining the group. Set false to keep only the hooks the demo actually exercises"
}
variable "terminating_default_result" {
  type        = string
  default     = "CONTINUE"
  description = "What Auto Scaling does if nothing completes the terminating action within the heartbeat. CONTINUE as the _monolithic template had it: the termination proceeds. ABANDON would fail the scale-in instead, which is the wrong trade - a node that could not be drained in time still has to go"

  validation {
    condition     = contains(["CONTINUE", "ABANDON"], var.terminating_default_result)
    error_message = "terminating_default_result must be either CONTINUE or ABANDON."
  }
}
variable "launching_default_result" {
  type        = string
  default     = "ABANDON"
  description = "What Auto Scaling does if nothing completes the launching action within the heartbeat. ABANDON as the _monolithic template had it: the instance is terminated rather than added to the group"

  validation {
    condition     = contains(["CONTINUE", "ABANDON"], var.launching_default_result)
    error_message = "launching_default_result must be either CONTINUE or ABANDON."
  }
}
variable "heartbeat_timeout_seconds" {
  type        = number
  default     = 300
  description = "How long the instance is held in the wait state before default_result applies, five minutes as the _monolithic template had it. Has to be longer than a drain takes or the hook releases the instance mid-drain - and note it is entirely separate from the two minutes a spot interruption gives, which no hook can extend"

  validation {
    condition     = var.heartbeat_timeout_seconds >= 30 && var.heartbeat_timeout_seconds <= 7200
    error_message = "heartbeat_timeout_seconds must be between 30 and 7200."
  }
}
