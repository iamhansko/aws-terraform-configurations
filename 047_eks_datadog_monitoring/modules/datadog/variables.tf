variable "api_key" {
  type        = string
  sensitive   = true
  description = "Datadog API key. sensitive so it is not printed by plan or apply, and no default on purpose: a key belongs to an account and hardcoding one would put a working credential in the repository. Pass it with TF_VAR_datadog_api_key from the root"

  validation {
    # Datadog API keys are 32 hexadecimal characters. Checking the shape here turns a
    # mistyped or truncated key into a plan-time error; otherwise the agent installs
    # cleanly and simply never reports, and the only sign is an empty dashboard
    # (rules.md B-1).
    condition     = can(regex("^[0-9a-f]{32}$", var.api_key))
    error_message = "api_key must be 32 lowercase hexadecimal characters, which is the shape of a Datadog API key. An app key is 40 characters and is not interchangeable."
  }
}
variable "namespace" {
  type        = string
  default     = "monitoring"
  description = "Namespace the operator, the API key Secret and the DatadogAgent all live in. One namespace for all three because the DatadogAgent's apiSecret reference resolves in its own namespace - a Secret elsewhere is not found, and the operator reports that only in its own log"

  validation {
    condition     = can(regex("^[a-z0-9]([-a-z0-9]*[a-z0-9])?$", var.namespace))
    error_message = "namespace must be a valid lowercase RFC 1123 DNS label."
  }
}
variable "release_name" {
  type        = string
  default     = "datadog-operator"
  description = "Helm release name for the Datadog operator"

  validation {
    condition     = can(regex("^[a-z0-9]([-a-z0-9]*[a-z0-9])?$", var.release_name))
    error_message = "release_name must be a valid lowercase RFC 1123 DNS label."
  }
}
variable "chart_version" {
  type        = string
  default     = "2.7.0"
  description = "Pinned datadog-operator chart version. The _monolithic template pinned nothing, so an apply months later would install whatever was current and the DatadogAgent CRD's apiVersion could move underneath it"

  validation {
    condition     = can(regex("^[0-9]+\\.[0-9]+\\.[0-9]+$", var.chart_version))
    error_message = "chart_version must be a semantic version, e.g. 2.7.0."
  }
}
variable "chart_repository" {
  type        = string
  default     = "https://helm.datadoghq.com"
  description = "Helm repository hosting the datadog-operator chart"

  validation {
    condition     = can(regex("^(https://|oci://)", var.chart_repository))
    error_message = "chart_repository must be an https:// or oci:// URL."
  }
}
variable "secret_name" {
  type        = string
  default     = "datadog-secret"
  description = "Name of the Secret holding the API key. The DatadogAgent references it by name, so the two move together"

  validation {
    condition     = can(regex("^[a-z0-9]([-a-z0-9.]*[a-z0-9])?$", var.secret_name))
    error_message = "secret_name must be a valid lowercase Kubernetes Secret name."
  }
}
variable "agent_name" {
  type        = string
  default     = "datadog"
  description = "Name of the DatadogAgent custom resource the operator reconciles into the agent DaemonSet"

  validation {
    condition     = can(regex("^[a-z0-9]([-a-z0-9]*[a-z0-9])?$", var.agent_name))
    error_message = "agent_name must be a valid lowercase RFC 1123 DNS label."
  }
}
variable "site" {
  type        = string
  default     = "datadoghq.com"
  description = "Datadog site the agent reports to. Must match the region the account was created in - a key from a datadoghq.eu account sends to datadoghq.com successfully at the TCP level and is then rejected, which looks like a bad key"

  validation {
    condition = contains([
      "datadoghq.com", "us3.datadoghq.com", "us5.datadoghq.com",
      "datadoghq.eu", "ddog-gov.com", "ap1.datadoghq.com", "ap2.datadoghq.com",
    ], var.site)
    error_message = "site must be one of Datadog's documented sites: datadoghq.com, us3.datadoghq.com, us5.datadoghq.com, datadoghq.eu, ddog-gov.com, ap1.datadoghq.com, ap2.datadoghq.com."
  }
}
variable "enable_log_collection" {
  type        = bool
  default     = true
  description = "Whether the agent collects container logs, as the _monolithic template had it. Turning this off leaves metrics working and logs absent, which is the configuration most of the Datadog quickstart screenshots assume is on"
}
variable "collect_all_containers" {
  type        = bool
  default     = true
  description = "Whether log collection covers every container rather than only those opted in with an annotation. True, as the _monolithic template had it: without it the agent collects nothing until pods are annotated, so a fresh cluster shows no logs and looks misconfigured"
}
variable "timeout_seconds" {
  type        = number
  default     = 600
  description = "How long to wait for the operator release to become ready. The operator has to be Available before its CRDs exist, and the DatadogAgent below cannot be applied until they are registered"

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
  description = "Extra chart values. type is auto when omitted and may only be auto or string, so a caller can force a value the chart must receive as a string (rules.md E-7)"

  validation {
    condition     = alltrue([for v in var.additional_set_values : v.type == null || contains(["auto", "string"], v.type)])
    error_message = "additional_set_values type must be omitted, \"auto\" or \"string\" - the only values helm_release accepts."
  }
}
