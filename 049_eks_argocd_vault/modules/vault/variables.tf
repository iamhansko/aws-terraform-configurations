variable "release_name" {
  type        = string
  default     = "vault"
  description = "Helm release name. The chart names its Ingress after it, and that name is the second half of the stack tag the pre-created ALB must carry to be adopted (rules.md G-3)"

  validation {
    condition     = can(regex("^[a-z0-9]([-a-z0-9]*[a-z0-9])?$", var.release_name))
    error_message = "release_name must be a valid lowercase RFC 1123 DNS label."
  }
}
variable "namespace" {
  type        = string
  default     = "vault"
  description = "Namespace Vault runs in, and the first half of the adoption stack tag (rules.md G-3)"

  validation {
    condition     = can(regex("^[a-z0-9]([-a-z0-9]*[a-z0-9])?$", var.namespace))
    error_message = "namespace must be a valid lowercase RFC 1123 DNS label."
  }
}
variable "chart_version" {
  type        = string
  default     = "0.34.1"
  description = "Pinned hashicorp/vault chart version. The _monolithic template pinned nothing, so a later apply would install whatever was current - and this chart's value paths have moved between versions, which is the class of change that breaks a configuration silently"

  validation {
    condition     = can(regex("^[0-9]+\\.[0-9]+\\.[0-9]+$", var.chart_version))
    error_message = "chart_version must be a semantic version, e.g. 0.34.1."
  }
}
variable "chart_repository" {
  type        = string
  default     = "https://helm.releases.hashicorp.com"
  description = "Helm repository hosting the Vault chart"

  validation {
    condition     = can(regex("^(https://|oci://)", var.chart_repository))
    error_message = "chart_repository must be an https:// or oci:// URL."
  }
}
variable "ingress_enabled" {
  type        = bool
  default     = true
  description = "Whether the chart creates an Ingress for the Vault UI. True, because the pre-created ALB is adopted from that Ingress - with it false the load balancer exists and nothing ever claims it (rules.md G-3)"
}
variable "ingress_class_name" {
  type        = string
  default     = "alb"
  description = "IngressClass the Vault Ingress asks for. alb, which is the class the AWS Load Balancer Controller owns - an Ingress naming a class no controller reconciles is created successfully and then never gets an address (rules.md G-1)"

  validation {
    condition     = can(regex("^[a-z0-9]([-a-z0-9]*[a-z0-9])?$", var.ingress_class_name))
    error_message = "ingress_class_name must be a valid lowercase RFC 1123 DNS label."
  }
}
variable "ingress_annotations" {
  type        = map(string)
  default     = {}
  description = "Annotations on the Vault Ingress, passed as a map and rendered through yamlencode so the dots in the keys need no escaping. The caller supplies the scheme, the target type and the frontend security group, because those have to agree with the pre-created ALB it also owns (rules.md B-6/G-3)"

  validation {
    condition     = alltrue([for key in keys(var.ingress_annotations) : length(key) > 0])
    error_message = "ingress_annotations must not contain empty keys."
  }
}
variable "ingress_hosts" {
  type = list(object({
    host  = string
    paths = optional(list(string), ["/"])
  }))
  default = [{
    # An empty host, which is how this chart is asked for a rule that matches any host - and a rule
    # matching any host is what a load balancer reached by its own generated DNS name needs, since
    # that name is not known to the chart.
    #
    # It has to be an entry rather than an empty list. The chart's template writes "rules:" and then
    # ranges over this value, so an empty list renders "rules:" with nothing under it - which reaches
    # the API server as rules: null and is rejected:
    #
    #   Ingress.networking.k8s.io "vault" is invalid: spec: Invalid value:
    #   []networking.IngressRule(nil): either `defaultBackend` or `rules` must be specified
    #
    # The template emits "- host: {{ .host | quote }}" unconditionally, so there is no way to get a
    # rule with the host key absent; an explicit empty string is the available equivalent, and
    # Kubernetes validates host only when it is non-empty.
    host  = ""
    paths = ["/"]
  }]
  description = <<-DESC
    Host rules for the Ingress, one entry per host.

    The default is a single entry with an empty host, which matches any host - appropriate for a load
    balancer reached by its own generated DNS name. Name a real host here once there is a DNS record
    pointing at the load balancer and the demo should answer only on that name.

    Not allowed to be empty while ingress_enabled is true: the chart ranges over this list to build
    spec.rules, so an empty list produces an Ingress with no rules and the API server rejects it.
  DESC

  validation {
    # The constraint is about the pair, so it cannot be stated on either value alone (rules.md B-1).
    # Worth checking here because the failure is a rejected manifest partway through a Helm install,
    # which leaves the release in `failed` state - and every apply after that reports only "cannot
    # re-use a name that is still in use" (rules.md E-7).
    condition     = var.ingress_enabled == false || length(var.ingress_hosts) > 0
    error_message = "ingress_hosts must contain at least one entry when ingress_enabled is true. The chart builds spec.rules by ranging over this list, so an empty one renders an Ingress with no rules and the API server rejects it with \"either `defaultBackend` or `rules` must be specified\" - which fails the Helm install and leaves the release stuck in `failed` state. Use a single entry with host = \"\" to match any host."
  }

  validation {
    condition     = alltrue([for h in var.ingress_hosts : length(h.paths) > 0])
    error_message = "each ingress_hosts entry must list at least one path; a host with no paths renders a rule with an empty paths array, which the API server also rejects."
  }
}
variable "data_storage_enabled" {
  type        = bool
  default     = true
  description = "Whether Vault's server gets a PersistentVolumeClaim, as the chart defaults it. True keeps Vault's data across a pod restart; it also means this release cannot become ready until a CSI driver can provision the volume"
}
variable "data_storage_size" {
  type        = string
  default     = "10Gi"
  description = "Size of Vault's data volume, the chart's own default"

  validation {
    condition     = can(regex("^[0-9]+(Mi|Gi|Ti)$", var.data_storage_size))
    error_message = "data_storage_size must be a Kubernetes quantity such as 10Gi."
  }
}
variable "storage_class" {
  type        = string
  description = "StorageClass the server's claim names. Required rather than optional, and not defaulted to null the way the chart does: a claim with no class resolves to whichever class is annotated default, and on a fresh EKS cluster at Kubernetes 1.33 none is - the built-in gp2 uses the in-tree provisioner removed in 1.23 and carries no default annotation. The claim then binds to nothing and vault-0 stays Pending, which fails the root's bootstrap association rather than this release. Pass the csi_storage_classes module's output (rules.md B-5)"

  validation {
    condition     = can(regex("^[a-z0-9]([-a-z0-9.]*[a-z0-9])?$", var.storage_class))
    error_message = "storage_class must be a valid lowercase RFC 1123 subdomain, and must name a StorageClass that exists in the cluster - an empty string would disable dynamic provisioning entirely, leaving the claim waiting for a PersistentVolume nothing creates."
  }
}
variable "timeout_seconds" {
  type        = number
  default     = 600
  description = "How long to wait for the release. Vault's pod reports itself unhealthy until it is initialised and unsealed, so this waits on the objects existing rather than on Vault being usable"

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
    error_message = "additional_set_values type must be omitted, \"auto\" or \"string\" - the only values helm_release accepts."
  }
}

variable "wait_for_release" {
  type        = bool
  default     = false
  description = <<-DESC
    Whether the apply waits for the release's pods to become Ready.

    False, and pinned false, because Ready is not reachable at install time. The chart's readiness
    probe is `vault status -tls-skip-verify`, and that command's exit code is the seal status - 0
    unsealed, 2 sealed. A newly installed Vault is uninitialised and sealed, so the probe fails until
    something runs `vault operator init` and `vault operator unseal`.

    In this project that something is the bootstrap SSM Association in the root, which is ordered
    after this release. So a true here waits for a step that cannot run until this one returns: the
    install burns its whole timeout, the release is left `failed`, and the next apply reports only
    "cannot re-use a name that is still in use" (rules.md E-7).
  DESC

  validation {
    # A constant condition rather than a cross-variable one: the constraint is not about a
    # combination, it is about this chart in this project (rules.md B-1).
    condition     = var.wait_for_release == false
    error_message = "wait_for_release must stay false. The chart's readiness probe reports Vault's seal status, so a newly installed Vault is never Ready - and the step that unseals it runs after this release. Waiting here leaves the release in `failed` state and every later apply fails with \"cannot re-use a name that is still in use\". To wait for Vault to be usable, wait on the bootstrap association in the root instead (rules.md E-7)."
  }
}
