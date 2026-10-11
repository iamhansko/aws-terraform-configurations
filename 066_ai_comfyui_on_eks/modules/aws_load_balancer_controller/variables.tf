variable "cluster_name" {
  type        = string
  description = "Name of the EKS cluster the controller manages load balancers for. Written into the chart's clusterName value, which the controller also uses to tag the load balancers it owns"

  validation {
    condition     = length(var.cluster_name) > 0
    error_message = "cluster_name must not be empty."
  }
}
variable "vpc_id" {
  type        = string
  description = "VPC ID the controller creates load balancers in. Passed explicitly so the controller does not have to discover it through IMDS"

  validation {
    condition     = can(regex("^vpc-[0-9a-f]+$", var.vpc_id))
    error_message = "vpc_id must be a valid VPC ID (e.g. vpc-0123456789abcdef0)."
  }
}
variable "aws_region" {
  type        = string
  description = "AWS region the controller operates in"

  validation {
    condition     = can(regex("^[a-z]{2}-[a-z]+-[0-9]$", var.aws_region))
    error_message = "aws_region must be a valid AWS region name (e.g. ap-northeast-2)."
  }
}
variable "namespace" {
  type        = string
  default     = "kube-system"
  description = "Namespace the controller and its service account are installed into. Baked into the IRSA trust policy's sub condition, so it must match the Helm release's namespace"

  validation {
    condition     = length(var.namespace) > 0
    error_message = "namespace must not be empty."
  }
}
variable "service_account_name" {
  type        = string
  default     = "aws-load-balancer-controller"
  description = "Kubernetes service account name the controller runs as, annotated with the IRSA role ARN"

  validation {
    condition     = length(var.service_account_name) > 0
    error_message = "service_account_name must not be empty."
  }
}
variable "release_name" {
  type        = string
  default     = "aws-load-balancer-controller"
  description = "Name of the Helm release"

  validation {
    condition     = length(var.release_name) > 0
    error_message = "release_name must not be empty."
  }
}
variable "chart_repository" {
  type        = string
  default     = "https://aws.github.io/eks-charts"
  description = "Helm repository hosting the aws-load-balancer-controller chart"

  validation {
    condition     = can(regex("^(https://|oci://)", var.chart_repository))
    error_message = "chart_repository must be an https:// or oci:// URL."
  }
}
variable "chart_version" {
  type        = string
  default     = "1.14.1"
  description = "Version of the aws-load-balancer-controller Helm chart. Pinned rather than floating so a re-apply months later installs the same controller"

  validation {
    condition     = can(regex("^[0-9]+\\.[0-9]+\\.[0-9]+$", var.chart_version))
    error_message = "chart_version must be a semantic version (e.g. 1.14.1)."
  }
}
variable "replica_count" {
  type        = number
  default     = 2
  description = "Number of controller replicas. The chart runs them as an active/standby leader-elected pair"

  validation {
    condition     = var.replica_count > 0
    error_message = "replica_count must be greater than zero."
  }
}
variable "timeout_seconds" {
  type        = number
  default     = 600
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
variable "enable_backend_security_group" {
  type        = bool
  default     = true
  description = "Whether the controller uses a shared backend security group (the k8s-traffic-<cluster>-<hash> group it creates, attaches to every load balancer, and names as the traffic source in the rules it adds to node/ENI security groups). Maps to the controller's --enable-backend-security-group flag, whose own default is true. Set false to get the pre-v2.3.0 behaviour, where node-side rules reference each load balancer's own frontend security group instead - one fewer security group, at the cost of a rule per load balancer on the node security group, which can hit the per-group rule limit once there are many load balancers. The controller requires it true when an Ingress or Service supplies its own frontend security group together with the manage-backend-security-group-rules annotation, and refuses that combination otherwise - the load balancer then provisions but never reaches the pods, with the reason only in the controller log. That constraint is deliberately not enforced here: this module installs the controller and cannot see what its caller's workload annotates, so any constant condition would be wrong for half its callers. It belongs to whichever root sets that annotation, which is the only place both halves of the pair are visible - those roots declare their own enable_backend_security_group variable carrying the validation. A root whose workload does not set the annotation has nothing to enforce and passes no value at all, leaving this default (rules.md B-1/G-2)"
}
variable "enable_service_mutator_webhook" {
  type        = bool
  default     = true
  description = "Whether the chart installs the mservice.elbv2.k8s.aws mutating webhook, which makes this controller the default for new Services of type LoadBalancer by injecting spec.loadBalancerClass. Maps to the chart's enableServiceMutatorWebhook value, whose own default is true, so this default matches the chart. It is only needed by a Service of type LoadBalancer that does not carry the aws-load-balancer-type: external annotation; a Service that sets that annotation is claimed by the controller without it (rules.md G-1). Set false where nothing relies on it, because the chart gives this webhook failurePolicy: Fail and no namespaceSelector, so its rule matches every v1/services CREATE in the cluster: while the controller has no Ready pod backing aws-load-balancer-webhook-service, every Service created anywhere is rejected with \"no endpoints available for service aws-load-balancer-webhook-service\". That window opens during this release's own install - the webhook is registered before the Deployment is Available - and again on every controller rollout or node replacement, so a chart installing Services in parallel fails for a reason that names this webhook rather than itself. Whether anything relies on it is a property of the caller's workloads, which this module cannot see, so the decision is left to the root that can (rules.md B-1)"
}
