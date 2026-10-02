variable "oidc_provider_arn" {
  type        = string
  description = "ARN of the cluster's IAM OIDC provider, for the IRSA trust policy. Injected from the cluster module rather than looked up here (rules.md B-6)"

  validation {
    condition     = can(regex("^arn:aws:iam::[0-9]{12}:oidc-provider/", var.oidc_provider_arn))
    error_message = "oidc_provider_arn must be an IAM OIDC provider ARN."
  }
}
variable "oidc_issuer_host" {
  type        = string
  description = "The cluster's OIDC issuer without its scheme (oidc.eks.<region>.amazonaws.com/id/<id>), used as the condition key prefix in the trust policy"

  validation {
    condition     = can(regex("^oidc\\.eks\\.[a-z0-9-]+\\.amazonaws\\.com/id/[A-Z0-9]+$", var.oidc_issuer_host))
    error_message = "oidc_issuer_host must look like oidc.eks.<region>.amazonaws.com/id/<id>, with no https:// prefix."
  }
}
variable "queue_url" {
  type        = string
  description = "URL of the queue the handler polls. The URL, not the name and not the ARN - all three identify the same queue and the chart wants this one. Taken from the queue module's output so the two cannot disagree (rules.md B-5)"

  validation {
    condition     = can(regex("^https://sqs\\.[a-z0-9-]+\\.amazonaws\\.com/[0-9]{12}/", var.queue_url))
    error_message = "queue_url must be an SQS queue URL (https://sqs.<region>.amazonaws.com/<account>/<name>)."
  }
}
variable "queue_arn" {
  type        = string
  description = "ARN of the same queue, used to scope the handler's sqs:ReceiveMessage and sqs:DeleteMessage to it. Taken separately rather than derived from the URL, because deriving it would put a second, independent definition of the queue's identity in this module"

  validation {
    condition     = can(regex("^arn:aws:sqs:", var.queue_arn))
    error_message = "queue_arn must be an SQS queue ARN."
  }
}
variable "aws_region" {
  type        = string
  description = "Region the handler makes its AWS calls in. Passed explicitly rather than left to the pod environment, as the chart's queue-mode documentation asks"

  validation {
    condition     = can(regex("^[a-z]{2}(-[a-z]+)+-[0-9]$", var.aws_region))
    error_message = "aws_region must be an AWS region code (e.g. ap-northeast-2)."
  }
}
variable "release_name" {
  type        = string
  default     = "aws-node-termination-handler"
  description = "Helm release name"

  validation {
    condition     = can(regex("^[a-z0-9]([-a-z0-9]*[a-z0-9])?$", var.release_name))
    error_message = "release_name must be a valid lowercase RFC 1123 DNS label."
  }
}
variable "namespace" {
  type        = string
  default     = "kube-system"
  description = "Namespace the handler runs in, as the _monolithic template had it"

  validation {
    condition     = can(regex("^[a-z0-9]([-a-z0-9]*[a-z0-9])?$", var.namespace))
    error_message = "namespace must be a valid lowercase RFC 1123 DNS label."
  }
}
variable "service_account_name" {
  type        = string
  default     = "aws-node-termination-handler"
  description = "Service account the handler runs as, and the subject of the IRSA trust policy. The trust condition pins this exact name, so changing it here changes both sides at once - which is the point of it being one variable"

  validation {
    condition     = can(regex("^[a-z0-9]([-a-z0-9.]*[a-z0-9])?$", var.service_account_name))
    error_message = "service_account_name must be a valid lowercase RFC 1123 subdomain."
  }
}
variable "chart" {
  type        = string
  default     = "oci://public.ecr.aws/aws-ec2/helm/aws-node-termination-handler"
  description = "OCI reference for the chart, as the _monolithic template had it. An OCI registry rather than an https repository, so helm takes the whole reference as the chart with no separate repository argument"

  validation {
    condition     = startswith(var.chart, "oci://")
    error_message = "chart must be an oci:// reference; an https repository needs a separate repository argument this module does not pass."
  }
}
variable "chart_version" {
  type        = string
  default     = "0.27.6"
  description = "Pinned chart version, where the _monolithic template pinned nothing. This component decides whether a node is drained before it disappears, so an unpinned upgrade changes that behaviour at the worst possible moment"

  validation {
    condition     = can(regex("^[0-9]+\\.[0-9]+\\.[0-9]+$", var.chart_version))
    error_message = "chart_version must be a semantic version (e.g. 0.27.6)."
  }
}
variable "replica_count" {
  type        = number
  default     = 3
  description = "Replicas of the queue-processor Deployment, three as the _monolithic template had it. They are not sharded - each polls the same queue and SQS hands a message to one of them - so this buys availability rather than throughput. The chart warns that more than one can send duplicate webhooks, which does not apply here since no webhook is configured"

  validation {
    condition     = var.replica_count >= 1
    error_message = "replica_count must be at least 1."
  }
}
variable "check_tag_before_draining" {
  type        = bool
  default     = true
  description = "Whether the handler only acts on instances carrying managed_tag. True in the chart by default, and set explicitly here because leaving it implicit hides the sharpest edge in this configuration: an untagged node group is silently never drained. The notice arrives, the handler decides the instance is not its business, and the node disappears with no drain and no error"
}
variable "managed_tag" {
  type        = string
  default     = "aws-node-termination-handler/managed"
  description = "Tag key the handler looks for when check_tag_before_draining is on. Should come from the same value the node groups write onto their instances, so the two cannot drift apart (rules.md B-5)"

  validation {
    condition     = length(var.managed_tag) > 0
    error_message = "managed_tag must not be empty."
  }
}
variable "node_termination_grace_period" {
  type        = number
  default     = 120
  description = "Seconds the handler waits for pods to leave after issuing the eviction. The chart's default, and effectively a ceiling rather than a target: a spot interruption gives two minutes in total, so a value near this leaves no time for the drain itself"

  validation {
    condition     = var.node_termination_grace_period > 0
    error_message = "node_termination_grace_period must be positive."
  }
}
variable "taint_node" {
  type        = bool
  default     = true
  description = "Whether the handler taints the node as well as cordoning it. Off in the chart by default; on here because a cordon alone only stops new pods from being scheduled, and a pod that tolerates an unschedulable node would stay put - which in this demo reads as the drain having failed"
}
variable "emit_kubernetes_events" {
  type        = bool
  default     = true
  description = "Whether the handler records what it did as Kubernetes events on the node. Off in the chart by default; on here so the drain is visible to kubectl get events rather than only in the handler's own log, which is the difference between a demo someone else can read and one only its author can"
}
variable "timeout_seconds" {
  type        = number
  default     = 600
  description = "How long to wait for the Deployment to become available"

  validation {
    condition     = var.timeout_seconds > 0
    error_message = "timeout_seconds must be positive."
  }
}
variable "additional_set_values" {
  type = list(object({
    name  = string
    value = string
    type  = optional(string)
  }))
  default     = []
  description = "Extra chart values. type is auto when omitted and may only be auto or string (rules.md E-7)"

  validation {
    condition     = alltrue([for v in var.additional_set_values : v.type == null || contains(["auto", "string"], v.type)])
    error_message = "additional_set_values type must be omitted, \"auto\" or \"string\"."
  }
}
