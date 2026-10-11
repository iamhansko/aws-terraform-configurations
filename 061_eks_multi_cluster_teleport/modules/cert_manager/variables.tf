variable "release_name" {
  type        = string
  default     = "cert-manager"
  description = "Helm release name. Also the service account name the chart creates, which is what the IRSA trust policy below names"

  validation {
    condition     = can(regex("^[a-z0-9]([-a-z0-9]*[a-z0-9])?$", var.release_name))
    error_message = "release_name must be a valid lowercase RFC 1123 DNS label."
  }
}
variable "namespace" {
  type        = string
  default     = "cert-manager"
  description = "Namespace cert-manager is installed into. Its own namespace, which is what the chart expects, and part of the IRSA trust policy's sub condition"

  validation {
    condition     = can(regex("^[a-z0-9]([-a-z0-9]*[a-z0-9])?$", var.namespace))
    error_message = "namespace must be a valid lowercase RFC 1123 DNS label."
  }
}
variable "chart_repository" {
  type        = string
  default     = "https://charts.jetstack.io"
  description = "Helm repository holding the cert-manager chart"

  validation {
    condition     = can(regex("^https://", var.chart_repository))
    error_message = "chart_repository must be an https URL."
  }
}
variable "chart_version" {
  type        = string
  default     = "v1.21.2"
  description = "Pinned cert-manager version. Pinned because the chart installs CRDs that other charts build Certificate objects against, and an unpinned upgrade can replace those CRDs underneath live objects"

  validation {
    condition     = can(regex("^v?[0-9]+\\.[0-9]+\\.[0-9]+$", var.chart_version))
    error_message = "chart_version must be a semantic version, optionally prefixed with v (e.g. v1.21.2)."
  }
}
variable "install_crds" {
  type        = bool
  default     = true
  description = "Whether the chart installs its CRDs. True, because the Teleport chart creates a Certificate object and that cannot exist before the CRD does. The value name matters: current charts call this crds.enabled, and the older installCRDs name is accepted and silently installs nothing"
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
variable "route53_hosted_zone_id" {
  type        = string
  description = "Hosted zone the DNS-01 solver writes challenge records into. Both the IAM policy and the ClusterIssuer are scoped to it, so the controller can only touch records in this one zone"

  validation {
    condition     = can(regex("^[A-Z0-9]{8,32}$", var.route53_hosted_zone_id))
    error_message = "route53_hosted_zone_id must be a hosted zone ID such as Z1234567890ABC - the bare ID, not the /hostedzone/... path Route 53 sometimes returns."
  }
}
variable "issuer_name" {
  type        = string
  default     = "letsencrypt"
  description = "Name of the ClusterIssuer. The Teleport chart references an issuer by name, so this value is read there too and is defined once (rules.md B-5)"

  validation {
    condition     = can(regex("^[a-z0-9]([-a-z0-9]*[a-z0-9])?$", var.issuer_name))
    error_message = "issuer_name must be a valid lowercase RFC 1123 DNS label."
  }
}
variable "issuer_email" {
  type        = string
  description = "Address Let's Encrypt associates with the account and uses for expiry notices. Required: the ACME server rejects a registration without one"

  validation {
    condition     = can(regex("^[^@[:space:]]+@[^@[:space:]]+\\.[^@[:space:]]+$", var.issuer_email))
    error_message = "issuer_email must be a single email address."
  }
}
variable "acme_server" {
  type        = string
  default     = "https://acme-v02.api.letsencrypt.org/directory"
  description = "ACME directory the issuer registers with. Production, as the _monolithic template had it - which also means production rate limits apply: five duplicate certificates per week per identifier. Point this at https://acme-staging-v02.api.letsencrypt.org/directory while iterating, and expect browsers to reject the resulting certificate"

  validation {
    condition     = can(regex("^https://", var.acme_server))
    error_message = "acme_server must be an https URL."
  }
}
variable "dns_zone" {
  type        = string
  description = "DNS zone the solver is selected for. cert-manager matches a solver to a challenge by this name, so a value that does not suffix the certificate's own names means no solver matches - and the Certificate sits Pending with no error on the object itself"

  validation {
    condition     = can(regex("^[a-z0-9]([-a-z0-9.]*[a-z0-9])?$", var.dns_zone))
    error_message = "dns_zone must be a lowercase DNS name such as example.com."
  }
}
variable "aws_region" {
  type        = string
  description = "Region the solver calls the Route 53 API in"

  validation {
    condition     = can(regex("^[a-z]{2}(-gov)?-[a-z]+-[0-9]$", var.aws_region))
    error_message = "aws_region must be a valid AWS region name."
  }
}
variable "timeout_seconds" {
  type        = number
  default     = 600
  description = "How long to wait for the release. cert-manager has to register its webhooks and pass its own readiness checks before anything can create an Issuer"

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
