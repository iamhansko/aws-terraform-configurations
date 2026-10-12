variable "cluster_name" {
  type        = string
  description = "Name of the EKS cluster Karpenter provisions nodes for"

  validation {
    condition     = length(var.cluster_name) > 0
    error_message = "cluster_name must not be empty."
  }
}
variable "oidc_provider_arn" {
  type        = string
  description = "ARN of the cluster's IAM OIDC provider, used as the Federated principal in the controller's IRSA trust policy"

  validation {
    condition     = can(regex("^arn:aws:iam::", var.oidc_provider_arn))
    error_message = "oidc_provider_arn must be a valid IAM OIDC provider ARN."
  }
}
variable "oidc_issuer_host" {
  type        = string
  description = "Cluster OIDC issuer URL without the https:// scheme, used in the trust policy's sub/aud condition keys"

  validation {
    condition     = length(var.oidc_issuer_host) > 0 && !can(regex("^https://", var.oidc_issuer_host))
    error_message = "oidc_issuer_host must be non-empty and must not include the https:// scheme."
  }
}
variable "namespace" {
  type        = string
  default     = "kube-system"
  description = "Namespace Karpenter's controller and service account are installed into. Baked into the IRSA trust policy's sub condition, so it must match the Helm release's namespace"

  validation {
    condition     = length(var.namespace) > 0
    error_message = "namespace must not be empty."
  }
}
variable "create_namespace" {
  type        = bool
  default     = false
  description = "Whether the Helm release creates its namespace. False by default because kube-system always exists; set true when installing into a dedicated karpenter namespace"
}
variable "service_account_name" {
  type        = string
  default     = "karpenter"
  description = "Kubernetes service account name the Karpenter controller runs as, annotated with the IRSA role ARN"

  validation {
    condition     = length(var.service_account_name) > 0
    error_message = "service_account_name must not be empty."
  }
}
variable "release_name" {
  type        = string
  default     = "karpenter"
  description = "Name of the Helm release"

  validation {
    condition     = length(var.release_name) > 0
    error_message = "release_name must not be empty."
  }
}
variable "chart_repository" {
  type        = string
  default     = "oci://public.ecr.aws/karpenter"
  description = "OCI registry hosting the Karpenter chart"

  validation {
    condition     = can(regex("^(https://|oci://)", var.chart_repository))
    error_message = "chart_repository must be an https:// or oci:// URL."
  }
}
variable "chart_version" {
  type        = string
  default     = "1.8.3"
  description = "Version of the Karpenter Helm chart. The chart also installs the NodePool and EC2NodeClass CRDs, so the apiVersions this module writes (karpenter.sh/v1, karpenter.k8s.aws/v1) must match the major version installed here"

  validation {
    condition     = can(regex("^[0-9]+\\.[0-9]+\\.[0-9]+$", var.chart_version))
    error_message = "chart_version must be a semantic version (e.g. 1.8.3)."
  }
}
variable "replica_count" {
  type        = number
  default     = 2
  description = "Number of Karpenter controller replicas, run as a leader-elected pair"

  validation {
    condition     = var.replica_count > 0
    error_message = "replica_count must be greater than zero."
  }
}
variable "controller_cpu_request" {
  type        = string
  default     = "1"
  description = "CPU request for the Karpenter controller pod"

  validation {
    condition     = can(regex("^([0-9]+m|[0-9]+(\\.[0-9]+)?)$", var.controller_cpu_request))
    error_message = "controller_cpu_request must be a Kubernetes CPU quantity (e.g. 1 or 500m)."
  }
}
variable "controller_memory_request" {
  type        = string
  default     = "1Gi"
  description = "Memory request for the Karpenter controller pod"

  validation {
    condition     = can(regex("^[0-9]+(Ei|Pi|Ti|Gi|Mi|Ki)$", var.controller_memory_request))
    error_message = "controller_memory_request must be a Kubernetes binary quantity (e.g. 1Gi)."
  }
}
variable "controller_cpu_limit" {
  type        = string
  default     = "1"
  description = "CPU limit for the Karpenter controller pod"

  validation {
    condition     = can(regex("^([0-9]+m|[0-9]+(\\.[0-9]+)?)$", var.controller_cpu_limit))
    error_message = "controller_cpu_limit must be a Kubernetes CPU quantity (e.g. 1 or 500m)."
  }
}
variable "controller_memory_limit" {
  type        = string
  default     = "1Gi"
  description = "Memory limit for the Karpenter controller pod"

  validation {
    condition     = can(regex("^[0-9]+(Ei|Pi|Ti|Gi|Mi|Ki)$", var.controller_memory_limit))
    error_message = "controller_memory_limit must be a Kubernetes binary quantity (e.g. 1Gi)."
  }
}
variable "interruption_queue_name" {
  type        = string
  default     = null
  description = "Name of an SQS queue receiving EC2 spot interruption and rebalance events, so Karpenter can drain a node before it is reclaimed. When null the setting is omitted and Karpenter runs without interruption handling, which is acceptable for on-demand-only pools"

  validation {
    condition     = var.interruption_queue_name == null || can(regex("^[A-Za-z0-9_-]{1,80}$", var.interruption_queue_name))
    error_message = "interruption_queue_name must be a valid SQS queue name, or null."
  }
  validation {
    # The pair, not either value on its own: a name without an ARN gives a controller pointed at
    # a queue it has no permission to read, which fails as a silent AccessDenied loop in its log
    # rather than as anything plan can see (rules.md B-1).
    condition     = var.interruption_queue_name == null || var.interruption_queue_arn != null || !var.create_controller_policy
    error_message = "interruption_queue_arn must be set alongside interruption_queue_name, so the created controller policy can grant sqs:ReceiveMessage on that queue. Pass both from the queue module's outputs, or set create_controller_policy = false and supply your own policy."
  }
}
variable "interruption_queue_arn" {
  type        = string
  default     = null
  description = "ARN of the interruption queue, used to scope the controller's sqs:ReceiveMessage and sqs:DeleteMessage to that one queue. Taken separately from interruption_queue_name rather than derived from it, because deriving the ARN would put a second, independent definition of the queue's identity in this module (rules.md B-5)"

  validation {
    condition     = var.interruption_queue_arn == null || can(regex("^arn:aws:sqs:", var.interruption_queue_arn))
    error_message = "interruption_queue_arn must be an SQS queue ARN, or null."
  }
}
variable "timeout_seconds" {
  type        = number
  default     = 900
  description = "How long to wait for the controller's Deployment to become Available before failing the apply"

  validation {
    condition     = var.timeout_seconds > 0
    error_message = "timeout_seconds must be greater than zero."
  }
}
variable "additional_set_values" {
  type = list(object({
    name  = string
    value = string
  }))
  default     = []
  description = "Extra Helm values appended to the release's set list, for chart settings this module does not expose as named variables"

  validation {
    condition     = alltrue([for entry in var.additional_set_values : length(entry.name) > 0])
    error_message = "additional_set_values entries must each have a non-empty name."
  }
}
variable "create_controller_policy" {
  type        = bool
  default     = true
  description = "Whether this module creates Karpenter's least-privilege controller policy and attaches it. On, because that is what the _monolithic template carried as an inline policy - and the alternative that looks simpler, attaching AdministratorAccess, gives a controller that can already launch and terminate instances the run of the whole account. Set false only to supply a policy of your own through controller_policy_arns"
}
variable "controller_policy_arns" {
  type        = list(string)
  default     = []
  description = "Additional managed policy ARNs attached to the controller's IRSA role, on top of the least-privilege policy this module creates. Empty by default: the created policy already covers everything Karpenter does, and anything added here widens it"

  validation {
    condition     = alltrue([for arn in var.controller_policy_arns : can(regex("^arn:aws:iam::", arn))])
    error_message = "controller_policy_arns must contain valid IAM policy ARNs."
  }
}
variable "node_iam_role_name" {
  type        = string
  default     = null
  description = "Optional fixed name for the role Karpenter-provisioned nodes run as. When null, a unique name is generated, which avoids collisions if this project is deployed twice in one account"

  validation {
    condition     = var.node_iam_role_name == null || can(regex("^[A-Za-z0-9+=,.@_-]{1,64}$", var.node_iam_role_name))
    error_message = "node_iam_role_name must be a valid IAM role name (64 characters or fewer), or null."
  }
}
variable "node_iam_policy_arns" {
  type = list(string)
  default = [
    "arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy",
    "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly",
    "arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy",
    "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore",
  ]
  description = "IAM managed policy ARNs attached to the role Karpenter-provisioned nodes run as"

  validation {
    condition     = alltrue([for arn in var.node_iam_policy_arns : can(regex("^arn:aws:iam::", arn))])
    error_message = "node_iam_policy_arns must contain valid IAM policy ARNs."
  }
}
