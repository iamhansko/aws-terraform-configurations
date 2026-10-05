variable "name" {
  type        = string
  default     = "multi-homed"
  description = "Base name. Each Deployment is named <name>-<attachment key> and selects on an app label of the same value, and every pod also carries a multus.terraform.io/workload label set to this, so all of them can be selected at once"

  validation {
    condition     = can(regex("^[a-z0-9]([-a-z0-9]*[a-z0-9])?$", var.name))
    error_message = "name must be a valid lowercase RFC 1123 DNS label."
  }
}
variable "namespace" {
  type        = string
  default     = "default"
  description = "Namespace the Deployment runs in, as the _monolithic template had it. Has to be the attachment's namespace, or the annotation needs the <namespace>/<name> form - Multus looks in the pod's own namespace otherwise and reports the attachment as missing"

  validation {
    condition     = can(regex("^[a-z0-9]([-a-z0-9]*[a-z0-9])?$", var.namespace))
    error_message = "namespace must be a valid lowercase RFC 1123 DNS label."
  }
}
variable "replicas_per_attachment" {
  type        = number
  default     = 1
  description = "How many pods to run per attachment. One, which is what makes each pod's secondary ENI its own: the pods of one Deployment all carry the same annotation, so a second replica would be a second pod on the same ENI and the ENI would be shared rather than dedicated. Raise it only if sharing is what you want"

  validation {
    condition     = var.replicas_per_attachment >= 1
    error_message = "replicas_per_attachment must be at least 1."
  }
}
variable "network_attachments" {
  type        = map(string)
  description = "The NetworkAttachmentDefinition each Deployment asks for, keyed by a caller-chosen label for it - the host interface it rides, in this project. One Deployment of replicas_per_attachment pods is created per entry, and each pod names only its own attachment, so the ENI behind it belongs to that pod alone. A map rather than a list because the names are another module's output and unknown until apply, while for_each needs keys that are known during plan (rules.md B-8)"

  validation {
    condition     = length(var.network_attachments) > 0
    error_message = "network_attachments must name at least one attachment."
  }
  validation {
    condition     = alltrue([for k in keys(var.network_attachments) : can(regex("^[a-z0-9]([-a-z0-9]*[a-z0-9])?$", k))])
    error_message = "network_attachments keys are appended to the Deployment name, so each must be a valid lowercase RFC 1123 DNS label."
  }
  validation {
    condition     = alltrue([for n in values(var.network_attachments) : can(regex("^[a-z0-9]([-a-z0-9]*[a-z0-9])?$", n))])
    error_message = "each value in network_attachments must be a valid lowercase RFC 1123 DNS label."
  }
  validation {
    # Two keys pointing at one attachment would put two pods on the same ENI, which is the
    # arrangement this module exists to avoid.
    condition     = length(distinct(values(var.network_attachments))) == length(var.network_attachments)
    error_message = "network_attachments must not point two keys at the same attachment - both pods would share that attachment's ENI instead of having one each."
  }
}
variable "image" {
  type        = string
  default     = "wbitt/network-multitool:3.22.2-extra"
  description = "Container image, a networking toolbox with ip, ping, curl and dig in it - which is the point, since the whole demo is running \"ip -brief address\" and pinging the other pod over the second interface. Pinned to a version tag, where the _monolithic template used the bare name wbitt/network-multitool and so got docker.io's floating latest from a registry that rate-limits anonymous pulls per source address"

  validation {
    condition     = can(regex(":[a-zA-Z0-9._-]+$|@sha256:[0-9a-f]{64}$", var.image))
    error_message = "image must carry an explicit tag or a digest."
  }
}
variable "node_selector" {
  type        = map(string)
  default     = {}
  description = "Labels a node must carry for these pods to land on it. Worth setting when only some node group's instances have the extra interfaces: a pod scheduled onto a node without them stays in ContainerCreating rather than falling back to one interface, so this is the difference between a clear failure and a stuck pod. Take the value from the node group's own labels rather than restating it (rules.md B-5)"

  validation {
    condition     = alltrue([for key in keys(var.node_selector) : length(key) > 0])
    error_message = "node_selector must not contain empty label keys."
  }
}
variable "network_attachment_revision" {
  type        = string
  default     = null
  description = "Digest of the attachment's CNI configuration, from the module that built it. Written into the pod template as an annotation so that changing the attachment - its subnet, range, master interface or mode - replaces these pods. Without it the attachment changes and the running pods keep the interfaces they were plumbed with, because Multus only reads the attachment at pod creation. Null omits the annotation, for a caller that would rather restart the workload by hand (rules.md B-4)"

  validation {
    condition     = var.network_attachment_revision == null || can(regex("^[0-9a-f]{6,64}$", var.network_attachment_revision))
    error_message = "network_attachment_revision must be a hexadecimal digest, or null to omit the annotation."
  }
}
variable "oidc_provider_arn" {
  type        = string
  description = "ARN of the cluster's IAM OIDC provider, which the initContainer's role trusts. From the cluster module rather than restated: a trust policy naming a different provider is accepted by IAM and fails only when a pod tries to assume the role (rules.md B-5)"

  validation {
    condition     = can(regex("^arn:aws[a-z-]*:iam::[0-9]{12}:oidc-provider/", var.oidc_provider_arn))
    error_message = "oidc_provider_arn must be an IAM OIDC provider ARN."
  }
}
variable "oidc_issuer_host" {
  type        = string
  description = "Host and path of the cluster's OIDC issuer, without the scheme - it is the prefix of the condition keys in the trust policy. From the cluster module for the same reason as oidc_provider_arn (rules.md B-5)"

  validation {
    condition     = can(regex("^oidc\\.eks\\.[a-z0-9-]+\\.amazonaws\\.com/id/[A-Z0-9]+$", var.oidc_issuer_host))
    error_message = "oidc_issuer_host must look like oidc.eks.<region>.amazonaws.com/id/<id>, with no https:// prefix - the condition keys in the trust policy are built from it directly."
  }
}
variable "region" {
  type        = string
  description = "Region the ENIs live in. Passed to the initContainer as AWS_REGION and used to scope the IAM policy, rather than left to the SDK to discover - a pod cannot always reach IMDS, which is where it would otherwise look"

  validation {
    condition     = can(regex("^[a-z]{2}(-gov)?-[a-z]+-[0-9]$", var.region))
    error_message = "region must be an AWS region name (e.g. ap-northeast-2)."
  }
}
variable "account_id" {
  type        = string
  description = "Account the ENIs live in, used to scope the IAM policy to this account's network interfaces"

  validation {
    condition     = can(regex("^[0-9]{12}$", var.account_id))
    error_message = "account_id must be a 12-digit AWS account ID."
  }
}
variable "partition" {
  type        = string
  default     = "aws"
  description = "ARN partition, so the policy's resource ARN is correct outside the commercial regions"

  validation {
    condition     = can(regex("^aws[a-z-]*$", var.partition))
    error_message = "partition must be an ARN partition such as aws, aws-cn or aws-us-gov."
  }
}
variable "secondary_interface_name" {
  type        = string
  default     = "net1"
  description = "Name of the Multus interface inside the pod, which the initContainer reads its MAC and address from. net1, because Multus numbers the interfaces it adds from one and each Deployment here names exactly one attachment. Not the host interface name - that is the ENI's, and Multus does not reuse it inside the pod"

  validation {
    condition     = can(regex("^net[0-9]+$", var.secondary_interface_name))
    error_message = "secondary_interface_name must look like net1 - that is the scheme Multus uses for the interfaces it adds, regardless of what the host interface is called."
  }
}
variable "ip_manager_image" {
  type        = string
  default     = "amazon/aws-cli:2.31.11"
  description = "Image for the sidecar that registers the pod's secondary address with the VPC and releases it again on shutdown. Chosen because it carries both the AWS CLI and python3, which is what the script needs - it reads the interface address through an ioctl, there being no iproute2 in this image. Pinned rather than :latest, because it runs alongside every pod"

  validation {
    condition     = can(regex(":[^:/]+$", var.ip_manager_image))
    error_message = "ip_manager_image must carry an explicit tag or digest."
  }
}
variable "ip_manager_cpu_request" {
  type        = string
  default     = "10m"
  description = "CPU request for the sidecar. It makes two API calls at startup and then one ioctl per watch interval, so this only has to be enough to be schedulable"

  validation {
    condition     = can(regex("^[0-9]+m?$", var.ip_manager_cpu_request))
    error_message = "ip_manager_cpu_request must be a Kubernetes CPU quantity (e.g. 10m)."
  }
}
variable "ip_manager_memory_request" {
  type        = string
  default     = "64Mi"
  description = "Memory request for the sidecar. The AWS CLI v2 is a bundled python runtime, so it needs more than a shell would, and unlike an initContainer this one holds it for the life of the pod"

  validation {
    condition     = can(regex("^[0-9]+(Ki|Mi|Gi)$", var.ip_manager_memory_request))
    error_message = "ip_manager_memory_request must be a Kubernetes memory quantity (e.g. 64Mi)."
  }
}
variable "iam_role_name_prefix" {
  type        = string
  default     = "multus-ip-manager-"
  description = "Prefix for the generated name of the sidecar's IAM role. A prefix rather than a name, so two deployments of this project in one account do not collide on it"

  validation {
    condition     = can(regex("^[a-zA-Z0-9+=,.@_-]{1,38}$", var.iam_role_name_prefix))
    error_message = "iam_role_name_prefix must be 1-38 characters IAM accepts in a role name, leaving room for the generated suffix."
  }
}
variable "ip_manager_watch_interval_seconds" {
  type        = number
  default     = 10
  description = "How often the sidecar re-reads its interface to notice that the address changed. Only an ioctl per interval; an API call happens only when the address actually moved. This is the part an initContainer could not do, and it is what a workload failing a floating address over between an active and a standby pod needs"

  validation {
    condition     = var.ip_manager_watch_interval_seconds >= 1 && var.ip_manager_watch_interval_seconds <= 300
    error_message = "ip_manager_watch_interval_seconds must be between 1 and 300."
  }
}
variable "ip_manager_startup_probe_period_seconds" {
  type        = number
  default     = 2
  description = "How often the sidecar's startup probe checks whether registration finished. The probe is what makes Kubernetes hold the application container until the address is routable - a sidecar is otherwise considered ready as soon as it has started, which an initContainer's exit guaranteed for free"

  validation {
    condition     = var.ip_manager_startup_probe_period_seconds >= 1
    error_message = "ip_manager_startup_probe_period_seconds must be at least 1."
  }
}
variable "ip_manager_startup_probe_failure_threshold" {
  type        = number
  default     = 60
  description = "How many probe failures to tolerate before the sidecar is restarted. Multiplied by the period this is the budget for two EC2 API calls, generous on purpose: the pod is useless until registration succeeds, so restarting the container quickly gains nothing and only hides the error in a crash loop"

  validation {
    condition     = var.ip_manager_startup_probe_failure_threshold >= 1
    error_message = "ip_manager_startup_probe_failure_threshold must be at least 1."
  }
}
variable "termination_grace_period_seconds" {
  type        = number
  default     = 45
  description = "How long the pod has to shut down, which the sidecar's preStop hook and the application's own shutdown share. Above the Kubernetes default of thirty, because the hook makes an EC2 API call: if the budget runs out the container is killed, the address stays assigned to the ENI, and nothing reports it"

  validation {
    condition     = var.termination_grace_period_seconds >= 10
    error_message = "termination_grace_period_seconds must be at least 10 - the preStop hook makes an EC2 API call and a shorter budget leaves the address assigned."
  }
}
