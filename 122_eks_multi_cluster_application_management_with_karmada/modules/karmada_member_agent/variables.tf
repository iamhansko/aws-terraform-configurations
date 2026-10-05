variable "cluster_name" {
  type        = string
  description = "Name this member registers under, which becomes the Cluster object's name on the Karmada API server. The root passes the member cluster's own EKS name so the two cannot diverge, and the demo PropagationPolicy refers to the same value (rules.md B-5)"

  validation {
    condition     = can(regex("^[a-z0-9]([-a-z0-9.]*[a-z0-9])?$", var.cluster_name))
    error_message = "cluster_name must be a valid lowercase RFC 1123 subdomain - it becomes the name of a Kubernetes object."
  }
}
variable "cluster_endpoint" {
  type        = string
  default     = null
  description = "The member cluster's own API server endpoint, recorded as spec.apiEndpoint on the Cluster object. Descriptive in pull mode - nothing connects to it - but worth setting, because without it `kubectl get clusters -o wide` shows no endpoint at all"

  validation {
    condition     = var.cluster_endpoint == null || can(regex("^https://", var.cluster_endpoint))
    error_message = "cluster_endpoint must be an https URL, or null."
  }
}
variable "karmada_api_endpoint" {
  type        = string
  description = "Address of the Karmada API server the agent connects to, with scheme and port. The load balancer's endpoint, not an in-cluster Service name: this pod runs in a different cluster. The certificate behind that address has to carry its name as a SAN"

  validation {
    condition     = can(regex("^https://", var.karmada_api_endpoint))
    error_message = "karmada_api_endpoint must be an https URL such as https://karmada-abc.elb.ap-northeast-2.amazonaws.com:32443."
  }
}
variable "karmada_ca_cert_pem" {
  type        = string
  description = "Karmada's server CA certificate, which the agent uses to verify the API server"

  validation {
    condition     = can(regex("BEGIN CERTIFICATE", var.karmada_ca_cert_pem))
    error_message = "karmada_ca_cert_pem must be a PEM-encoded certificate."
  }
}
variable "karmada_cert_pem" {
  type        = string
  description = "Client certificate the agent authenticates with. The same karmada certificate the control plane was installed with, which is a cluster administrator on the Karmada API server - the agent needs that much, because registering a cluster means creating objects in several API groups"

  validation {
    condition     = can(regex("BEGIN CERTIFICATE", var.karmada_cert_pem))
    error_message = "karmada_cert_pem must be a PEM-encoded certificate."
  }
}
variable "karmada_private_key_pem" {
  type        = string
  sensitive   = true
  description = "Its private key"

  validation {
    condition     = can(regex("PRIVATE KEY", var.karmada_private_key_pem))
    error_message = "karmada_private_key_pem must be a PEM-encoded private key."
  }
}
variable "release_name" {
  type        = string
  default     = "karmada-agent"
  description = "Helm release name, which prefixes the objects the chart creates in the member cluster. karmada-agent, as Karmada's own documentation installs it"

  validation {
    condition     = can(regex("^[a-z0-9]([-a-z0-9]*[a-z0-9])?$", var.release_name))
    error_message = "release_name must be a valid lowercase RFC 1123 label."
  }
}
variable "namespace" {
  type        = string
  default     = "karmada-system"
  description = "Namespace in the member cluster the agent runs in. Created by the release. The same name the control plane uses on the parent, which is only a convention - these are different clusters"

  validation {
    condition     = can(regex("^[a-z0-9]([-a-z0-9]*[a-z0-9])?$", var.namespace))
    error_message = "namespace must be a valid lowercase RFC 1123 label."
  }
}
variable "chart_repository" {
  type        = string
  default     = "https://raw.githubusercontent.com/karmada-io/karmada/master/charts"
  description = "Helm repository holding the Karmada chart - the same chart as the control plane's, with installMode flipped to agent"

  validation {
    condition     = can(regex("^(https://|oci://)", var.chart_repository))
    error_message = "chart_repository must be an https or oci URL."
  }
}
variable "chart_version" {
  type        = string
  default     = "v1.19.0"
  description = "Chart version, with the leading v the Karmada repository's index uses. The root passes the control plane's version so an agent is never a different Karmada release from the control plane it registers with (rules.md B-5)"

  validation {
    condition     = can(regex("^v[0-9]+\\.[0-9]+\\.[0-9]+$", var.chart_version))
    error_message = "chart_version must look like v1.19.0, including the leading v."
  }
}
variable "karmada_image_version" {
  type        = string
  default     = "v1.19.0"
  description = "Tag for the karmada-agent image. Set explicitly because the chart leaves it on :latest through a YAML anchor that user values cannot override - see modules/karmada_control_plane/main.tf"

  validation {
    condition     = can(regex("^v[0-9]+\\.[0-9]+\\.[0-9]+$", var.karmada_image_version))
    error_message = "karmada_image_version must look like v1.19.0."
  }
}
variable "replica_count" {
  type        = number
  default     = 1
  description = "Replicas of the agent Deployment. One is enough: the agent leader-elects, so extra replicas are standby rather than additional throughput"

  validation {
    condition     = var.replica_count >= 1
    error_message = "replica_count must be at least one."
  }
}
variable "timeout_seconds" {
  type        = number
  default     = 600
  description = "How long helm waits for the agent Deployment to become Available. Note what this does not cover: the agent creates its Cluster object after it starts, so a release that has finished is not yet a cluster that is registered"

  validation {
    condition     = var.timeout_seconds > 0
    error_message = "timeout_seconds must be positive."
  }
}
