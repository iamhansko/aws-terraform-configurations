variable "aws_region" {
  type        = string
  description = "Region written into the OUTPUT block's region field. Fluent Bit runs inside the Fargate infrastructure and does not inherit a region from the caller, so it has to be named explicitly"

  validation {
    condition     = can(regex("^[a-z]{2}(-[a-z]+)+-[0-9]+$", var.aws_region))
    error_message = "aws_region must be a region code like ap-northeast-2."
  }
}
variable "pod_execution_role_name" {
  type        = string
  description = "Name of the Fargate pod execution IAM role the kinesis:PutRecords policy is attached to. Fluent Bit writes as this role, not as anything the pod carries"

  validation {
    condition     = length(var.pod_execution_role_name) > 0
    error_message = "pod_execution_role_name must not be empty."
  }
}
variable "stream_name" {
  type        = string
  description = "Name of the Kinesis data stream Fluent Bit writes to. Pass the stream module's name output rather than restating it, so the ConfigMap cannot point at a stream that does not exist (rules.md B-5)"

  validation {
    condition     = can(regex("^[a-zA-Z0-9_.-]{1,128}$", var.stream_name))
    error_message = "stream_name must be 1-128 characters of letters, digits, underscores, dots or hyphens."
  }
}
variable "stream_arn" {
  type        = string
  description = "ARN of the same stream, used to scope the IAM policy. Taken as a separate input rather than rebuilt from stream_name, because building an ARN by string concatenation is how a policy ends up granting nothing in a different partition or account"

  validation {
    condition     = can(regex("^arn:aws[a-z-]*:kinesis:", var.stream_arn))
    error_message = "stream_arn must be a Kinesis stream ARN (arn:aws:kinesis:...)."
  }
}
variable "match" {
  type        = string
  default     = "*"
  description = "Fluent Bit tag pattern the OUTPUT block matches. '*' sends every record to the stream, which is what this variant demonstrates; the CloudWatch variant instead splits records across sinks by pod label"

  validation {
    condition     = length(var.match) > 0
    error_message = "match must not be empty - an OUTPUT block with no Match receives nothing."
  }
}
variable "namespace" {
  type        = string
  default     = "aws-observability"
  description = "Namespace holding the logging ConfigMap. EKS looks for this exact name and ignores anything else, so it is a variable only to keep the value out of the resource body"

  validation {
    condition     = var.namespace == "aws-observability"
    error_message = "namespace must be aws-observability. EKS enables Fargate logging by looking for a namespace with that exact name carrying the aws-observability: enabled label; any other name is silently ignored and pods produce no logs."
  }
}
variable "configmap_name" {
  type        = string
  default     = "aws-logging"
  description = "Name of the logging ConfigMap. Like the namespace, EKS looks for this exact name"

  validation {
    condition     = var.configmap_name == "aws-logging"
    error_message = "configmap_name must be aws-logging - the only name the Fargate log router reads."
  }
}
variable "policy_name" {
  type        = string
  default     = "FargatePodExecutionKinesisPolicy"
  description = "Name of the inline policy added to the pod execution role. The _monolithic template called this FargatePodExecutionFirehosePolicy in every variant including this one, which named the wrong sink"

  validation {
    condition     = can(regex("^[a-zA-Z0-9+=,.@_-]{1,128}$", var.policy_name))
    error_message = "policy_name must be 1-128 characters from the set IAM accepts for a policy name."
  }
}
variable "flb_log_cw" {
  type        = bool
  default     = false
  description = "Whether Fluent Bit ships its own process log to CloudWatch. Useful when records never reach the stream and the question is whether Fluent Bit even started - note this one output goes to CloudWatch regardless of the sink the workload's logs use"
}
