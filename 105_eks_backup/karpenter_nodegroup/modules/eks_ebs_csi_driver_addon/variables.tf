variable "cluster_name" {
  type        = string
  description = "Name of the EKS cluster the addon is installed on. Also the cluster the Pod Identity association is scoped to, which is why this module needs no OIDC provider ARN at all"

  validation {
    condition     = length(var.cluster_name) > 0
    error_message = "cluster_name must not be empty."
  }
}
variable "role_name" {
  type        = string
  default     = null
  description = "Optional fixed name for the driver's IAM role. Null generates one from role_name_prefix, which is what lets this project be deployed twice in one account. Set it only when something outside this configuration has to name the role - which is not the case here, unlike the cross-account replication role (rules.md I-2)"

  validation {
    condition     = var.role_name == null || can(regex("^[a-zA-Z0-9+=,.@_-]{1,64}$", var.role_name))
    error_message = "role_name must be 1-64 characters of the set IAM accepts for a role name, or null."
  }
}
variable "role_name_prefix" {
  type        = string
  default     = "ebs-csi-driver-"
  description = "Prefix for the generated role name when role_name is null"

  validation {
    condition     = can(regex("^[a-zA-Z0-9+=,.@_-]{1,32}$", var.role_name_prefix))
    error_message = "role_name_prefix must be 1-32 characters of the set IAM accepts for a role name."
  }
}
variable "service_account_name" {
  type        = string
  default     = "ebs-csi-controller-sa"
  description = "Service account the addon's controller runs as, and the one the Pod Identity association binds to the role. Decided by the addon rather than by this module, so changing it does not rename anything - it only breaks the association"

  validation {
    condition     = can(regex("^[a-z0-9]([-a-z0-9.]*[a-z0-9])?$", var.service_account_name))
    error_message = "service_account_name must be a valid lowercase RFC 1123 subdomain."
  }
}
variable "iam_policy_arns" {
  type        = list(string)
  default     = ["arn:aws:iam::aws:policy/service-role/AmazonEBSCSIDriverPolicy"]
  description = "Managed policies attached to the driver's role, as the _monolithic template had it. The AWS managed policy covers creating, attaching, deleting and snapshotting volumes the driver owns"

  validation {
    condition     = length(var.iam_policy_arns) > 0 && alltrue([for arn in var.iam_policy_arns : can(regex("^arn:aws:iam::", arn))])
    error_message = "iam_policy_arns must contain at least one valid IAM policy ARN."
  }
}
variable "grant_snapshot_tagging" {
  type        = bool
  default     = false
  description = "Whether to add ec2:CreateTags on volumes and snapshots the driver itself creates, scoped by the ec2:CreateAction condition. Off here: nothing in this project snapshots anything, and a permission granted for a workflow that does not exist is a permission nobody will remember to remove (rules.md A-5). Turn it on together with whatever takes the snapshots"
}
variable "addon_version" {
  type        = string
  default     = null
  description = "Addon version. Null lets EKS pick the default for the cluster's Kubernetes version"

  validation {
    condition     = var.addon_version == null || can(regex("^v[0-9]+\\.[0-9]+\\.[0-9]+-eksbuild\\.[0-9]+$", var.addon_version))
    error_message = "addon_version must look like v1.66.0-eksbuild.1, or null to let EKS choose."
  }
}
variable "resolve_conflicts_on_create" {
  type        = string
  default     = "OVERWRITE"
  description = "What EKS does when the addon's objects already exist at create time"

  validation {
    condition     = contains(["NONE", "OVERWRITE"], var.resolve_conflicts_on_create)
    error_message = "resolve_conflicts_on_create must be either NONE or OVERWRITE."
  }
}
variable "resolve_conflicts_on_update" {
  type        = string
  default     = "OVERWRITE"
  description = "What EKS does on update when a field has been changed outside the addon, as the _monolithic template set on every addon"

  validation {
    condition     = contains(["NONE", "OVERWRITE", "PRESERVE"], var.resolve_conflicts_on_update)
    error_message = "resolve_conflicts_on_update must be one of NONE, OVERWRITE or PRESERVE."
  }
}

variable "controller_tolerations" {
  type = list(object({
    key      = string
    operator = string
    value    = string
    effect   = string
  }))
  default     = []
  description = <<-DESC
    Tolerations for this addon's controller Deployment, in Kubernetes form.

    Needed when the only capacity the controller can be placed on is tainted. The node DaemonSet is
    unaffected - this addon's DaemonSet tolerates every taint by default - which is why a tainted node
    group produces a running DaemonSet, a Pending controller, and an addon reporting DEGRADED without
    naming either of them.

    Empty by default, which leaves the chart's own tolerations in place. A non-empty list replaces them
    rather than adding to them, because the addon's schema exposes one tolerations array and nothing to
    append to: pass the full set the controller needs.
  DESC

  validation {
    condition     = alltrue([for t in var.controller_tolerations : contains(["Exists", "Equal"], t.operator)])
    error_message = "each toleration operator must be Exists or Equal."
  }

  validation {
    condition     = alltrue([for t in var.controller_tolerations : contains(["NoSchedule", "PreferNoSchedule", "NoExecute"], t.effect)])
    error_message = "each toleration effect must be NoSchedule, PreferNoSchedule or NoExecute - the Kubernetes spelling, not the EKS API's NO_SCHEDULE."
  }
}

variable "controller_pod_annotations" {
  type        = map(string)
  default     = {}
  description = <<-DESC
    Annotations on this addon's controller pods.

    The reason this exists is eks.amazonaws.com/compute-type: ec2. On a cluster whose Fargate profile
    selects kube-system, every pod created there is claimed by fargate-scheduler, and this controller
    cannot run on Fargate - so without the annotation it is placed somewhere it will never work. That
    annotation is the documented way to keep a pod on EC2, and it is the same one EKS puts on CoreDNS.

    Empty by default: on a cluster with no Fargate profile there is nothing to opt out of.
  DESC
}
