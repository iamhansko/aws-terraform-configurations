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
  description = "Name of the Fargate pod execution IAM role the es:ESHttp* policy is attached to. Fluent Bit writes as this role, not as anything the pod carries"

  validation {
    condition     = length(var.pod_execution_role_name) > 0
    error_message = "pod_execution_role_name must not be empty."
  }
}
variable "opensearch_endpoint" {
  type        = string
  description = "Host part of the OpenSearch domain endpoint, with no scheme. Pass the domain module's endpoint output rather than restating it, so the ConfigMap cannot point at a domain that does not exist (rules.md B-5)"

  validation {
    condition     = can(regex("^[a-z0-9.-]+$", var.opensearch_endpoint)) && !can(regex("^https?://", var.opensearch_endpoint))
    error_message = "opensearch_endpoint must be a bare host with no scheme. Fluent Bit's Host field takes a hostname, and an https:// prefix makes every request fail to resolve."
  }
}
variable "opensearch_arn" {
  type        = string
  description = "ARN of the same domain, used to scope the IAM policy. Taken as a separate input rather than rebuilt from the endpoint, because building an ARN by string concatenation is how a policy ends up granting nothing"

  validation {
    condition     = can(regex("^arn:aws[a-z-]*:es:", var.opensearch_arn))
    error_message = "opensearch_arn must be an OpenSearch domain ARN (arn:aws:es:...)."
  }
}
variable "index_name" {
  type        = string
  default     = "web"
  description = "OpenSearch index Fluent Bit writes into. One index for everything, as the _monolithic template had it - the es output plugin takes a single Index, so per-application indices would need one OUTPUT block per index"

  validation {
    condition     = can(regex("^[a-z0-9][a-z0-9._-]*$", var.index_name))
    error_message = "index_name must be lowercase and start with a letter or digit - OpenSearch rejects uppercase index names."
  }
}
variable "include_kubernetes_filter" {
  type        = bool
  default     = false
  description = "Whether to add the kubernetes filter, which attaches pod name, namespace and labels to each record. False reproduces the _monolithic template for this variant, whose ConfigMap had no filters at all - so delivered objects hold the raw container log line and nothing else"
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
  default     = "FargatePodExecutionOpenSearchPolicy"
  description = "Name of the inline policy added to the pod execution role. The _monolithic template called this FargatePodExecutionFirehosePolicy in every variant including this one, which named the wrong sink"

  validation {
    condition     = can(regex("^[a-zA-Z0-9+=,.@_-]{1,128}$", var.policy_name))
    error_message = "policy_name must be 1-128 characters from the set IAM accepts for a policy name."
  }
}
variable "flb_log_cw" {
  type        = bool
  default     = null
  description = "Whether Fluent Bit ships its own process log to CloudWatch. Null omits the key entirely, which is what the _monolithic template did for this variant; true is worth setting when records never reach the domain and the question is whether Fluent Bit even started. Note this one output goes to CloudWatch regardless of where the workload's logs go"
}
