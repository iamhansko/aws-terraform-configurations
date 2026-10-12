variable "cluster_name" {
  type        = string
  description = "Name of the EKS cluster this controller manages. Passed to the chart as clusterName and used to scope the Pod Identity association, so the two cannot disagree - which is the bug the _monolithic template had when it installed the controller on the second cluster with the first cluster's name (rules.md G-3)"

  validation {
    condition     = length(var.cluster_name) > 0
    error_message = "cluster_name must not be empty."
  }
}
variable "vpc_id" {
  type        = string
  description = "VPC the load balancers are created in. Passed explicitly rather than left to the controller's IMDS lookup, so it does not depend on the node's metadata hop limit"

  validation {
    condition     = can(regex("^vpc-[0-9a-f]+$", var.vpc_id))
    error_message = "vpc_id must be a valid VPC ID (e.g. vpc-0123456789abcdef0)."
  }
}
variable "aws_region" {
  type        = string
  description = "Region the controller makes its AWS calls in. Passed as a variable rather than read from data.aws_region inside the module, because a module handed an aliased provider would otherwise be told the root's default region instead of its own (rules.md I-3)"

  validation {
    condition     = can(regex("^[a-z]{2}(-[a-z]+)+-[0-9]$", var.aws_region))
    error_message = "aws_region must be an AWS region code (e.g. ap-northeast-2)."
  }
}
variable "role_name" {
  type        = string
  default     = null
  description = "Optional fixed name for the controller's IAM role. Null generates one from role_name_prefix, which is what lets this project be deployed twice in one account"

  validation {
    condition     = var.role_name == null || can(regex("^[a-zA-Z0-9+=,.@_-]{1,64}$", var.role_name))
    error_message = "role_name must be 1-64 characters of the set IAM accepts for a role name, or null."
  }
}
variable "role_name_prefix" {
  type        = string
  default     = "aws-lbc-"
  description = "Prefix for the generated role name when role_name is null"

  validation {
    condition     = can(regex("^[a-zA-Z0-9+=,.@_-]{1,32}$", var.role_name_prefix))
    error_message = "role_name_prefix must be 1-32 characters of the set IAM accepts for a role name."
  }
}
variable "namespace" {
  type        = string
  default     = "kube-system"
  description = "Namespace the controller runs in, as the _monolithic template had it. Also the namespace the Pod Identity association is scoped to"

  validation {
    condition     = can(regex("^[a-z0-9]([-a-z0-9]*[a-z0-9])?$", var.namespace))
    error_message = "namespace must be a valid lowercase RFC 1123 DNS label."
  }
}
variable "service_account_name" {
  type        = string
  default     = "aws-load-balancer-controller"
  description = "Service account the controller runs as. The chart creates it and the Pod Identity association binds it, so this one variable decides both sides"

  validation {
    condition     = can(regex("^[a-z0-9]([-a-z0-9.]*[a-z0-9])?$", var.service_account_name))
    error_message = "service_account_name must be a valid lowercase RFC 1123 subdomain."
  }
}
variable "release_name" {
  type        = string
  default     = "aws-load-balancer-controller"
  description = "Helm release name"

  validation {
    condition     = can(regex("^[a-z0-9]([-a-z0-9]*[a-z0-9])?$", var.release_name))
    error_message = "release_name must be a valid lowercase RFC 1123 DNS label."
  }
}
variable "chart_repository" {
  type        = string
  default     = "https://aws.github.io/eks-charts"
  description = "Chart repository, as the _monolithic template's helm repo add did"

  validation {
    condition     = can(regex("^https://", var.chart_repository))
    error_message = "chart_repository must be an https URL."
  }
}
variable "chart_version" {
  type        = string
  default     = "1.14.1"
  description = "Pinned chart version, where the _monolithic template's helm install pinned nothing - so a stack created a month later got a different controller. Note the chart's own versioning is not the controller's: chart 1.14.1 carries controller v2.14.1"

  validation {
    condition     = can(regex("^[0-9]+\\.[0-9]+\\.[0-9]+$", var.chart_version))
    error_message = "chart_version must be a semantic version (e.g. 1.14.1)."
  }
}
variable "replica_count" {
  type        = number
  default     = 2
  description = "Controller replicas. Two so leader election has somewhere to fail over to, which matters in a project whose demo deliberately restores onto fresh nodes"

  validation {
    condition     = var.replica_count >= 1
    error_message = "replica_count must be at least 1."
  }
}
variable "enable_backend_security_group" {
  type        = bool
  default     = true
  description = "Whether the controller uses its shared backend security group. True here, which is the controller's own default: the demo Service does not set manage-backend-security-group-rules, so the controller writes the node-side rules itself against the group it creates - and with this off it would write none at all, leaving every target unhealthy with no error anywhere (rules.md G-2)"
}
variable "enable_service_mutator_webhook" {
  type        = bool
  default     = false
  description = "Whether the chart installs the mservice.elbv2.k8s.aws mutating webhook. Off, because the demo Service names this controller explicitly with the aws-load-balancer-type annotation, so the webhook has nothing to mutate - and its failurePolicy: Fail with no namespaceSelector would gate every Service creation in the cluster behind a controller pod being Ready (rules.md G-4)"
}
variable "timeout_seconds" {
  type        = number
  default     = 600
  description = "How long to wait for the controller's Deployment to become Available"

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
