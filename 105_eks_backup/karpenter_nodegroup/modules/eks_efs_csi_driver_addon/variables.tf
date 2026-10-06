variable "cluster_name" {
  type        = string
  description = "Name of the EKS cluster to install the aws-efs-csi-driver addon into"
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
  description = "Namespace the addon's controller service account lives in. Must match where EKS installs the addon, since it is baked into the IRSA trust policy's sub condition"
  validation {
    condition     = length(var.namespace) > 0
    error_message = "namespace must not be empty."
  }
}
variable "service_account_name" {
  type        = string
  default     = "efs-csi-controller-sa"
  description = "Service account name the EFS CSI controller runs as. Fixed by the addon; changing it breaks the IRSA trust policy's sub condition"
  validation {
    condition     = length(var.service_account_name) > 0
    error_message = "service_account_name must not be empty."
  }
}
variable "addon_version" {
  type        = string
  default     = null
  description = "Specific aws-efs-csi-driver addon version (e.g. v2.1.14-eksbuild.1). When null, EKS picks the default version for the cluster's Kubernetes version, which avoids pinning to a build a newer cluster no longer supports"
  validation {
    condition     = var.addon_version == null || can(regex("^v[0-9]+\\.[0-9]+\\.[0-9]+-eksbuild\\.[0-9]+$", var.addon_version))
    error_message = "addon_version must look like v2.1.14-eksbuild.1, or null."
  }
}
variable "configuration_values" {
  type        = string
  default     = null
  description = "Optional addon configuration as a JSON string, passed through to the addon's configuration_values. Left null by default so EKS applies its own defaults: the JSON schema differs per addon and per version, and an unrecognised key is only rejected at apply time. Confirm a value against 'aws eks describe-addon-configuration --addon-name aws-efs-csi-driver --addon-version <version>' before setting it (rules.md B-4/E-5)"
  validation {
    condition     = var.configuration_values == null || can(jsondecode(var.configuration_values))
    error_message = "configuration_values must be a valid JSON string, or null."
  }
}
variable "iam_policy_arns" {
  type        = list(string)
  default     = ["arn:aws:iam::aws:policy/service-role/AmazonEFSCSIDriverPolicy"]
  description = "IAM managed policy ARNs attached to the EFS CSI controller's IRSA role. AmazonEFSCSIDriverPolicy is what lets the controller create and delete the access points that back dynamically provisioned volumes"
  validation {
    condition     = alltrue([for arn in var.iam_policy_arns : can(regex("^arn:aws:iam::", arn))])
    error_message = "iam_policy_arns must contain valid IAM policy ARNs."
  }
}
variable "resolve_conflicts_on_create" {
  type        = string
  default     = "OVERWRITE"
  description = "How to resolve field value conflicts when creating an addon that is migrating from a pre-existing self-managed installation (e.g. the efs-csi-controller manifest the _monolithic design applied by hand)"
  validation {
    condition     = contains(["NONE", "OVERWRITE"], var.resolve_conflicts_on_create)
    error_message = "resolve_conflicts_on_create must be one of: NONE, OVERWRITE."
  }
}
variable "resolve_conflicts_on_update" {
  type        = string
  default     = "OVERWRITE"
  description = "How to resolve field value conflicts when updating the addon"
  validation {
    condition     = contains(["NONE", "OVERWRITE", "PRESERVE"], var.resolve_conflicts_on_update)
    error_message = "resolve_conflicts_on_update must be one of: NONE, OVERWRITE, PRESERVE."
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
