variable "role_name" {
  type        = string
  default     = "aws-fis-nth-queue-processor"
  description = "Name of the role. Exposed as a variable only so it is visible and documented, not so it can be changed: amazon-ec2-spot-interrupter hardcodes \"aws-fis-itn\" and will create its own role under that name if this one is called anything else, leaving two roles and an unexplained iam:CreateRole in the demo"
}
variable "managed_policy_arns" {
  type        = list(string)
  default     = ["arn:aws:iam::aws:policy/service-role/AWSFaultInjectionSimulatorEC2Access"]
  description = "Managed policies the role assumes to act on its targets. The EC2 access policy carries ec2:SendSpotInstanceInterruptions, which is the whole extent of what the CLI's experiments do. The _monolithic template also attached an inline policy granting fis:* on *, which an experiment role has no use for: it acts on EC2, not on FIS - the caller that starts the experiment is the one that needs FIS permissions, and here that is the bastion's instance role"

  validation {
    condition     = length(var.managed_policy_arns) > 0 && alltrue([for arn in var.managed_policy_arns : can(regex("^arn:aws:iam::", arn))])
    error_message = "managed_policy_arns must contain at least one valid IAM policy ARN; the tool attaches nothing to a role that already exists, so the permissions have to be complete here."
  }
}
variable "interrupt_delay" {
  type        = string
  default     = "13m"
  description = "Delay the interrupt command suggests between the rebalance recommendation, which the CLI sends immediately, and the two-minute interruption notice. Thirteen minutes as the _monolithic template's output had it, which is long enough to watch the handler react to the rebalance recommendation on its own before the interruption arrives - the real notice period is two minutes and nothing about that changes"

  validation {
    condition     = can(regex("^[0-9]+(s|m|h)$", var.interrupt_delay))
    error_message = "interrupt_delay must be a Go duration such as 15s, 13m or 1h."
  }
}
