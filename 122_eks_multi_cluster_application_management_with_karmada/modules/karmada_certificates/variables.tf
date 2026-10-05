variable "namespace" {
  type        = string
  default     = "karmada-system"
  description = "Namespace the control plane is installed into. Part of the in-cluster SANs, so it has to match the namespace the chart is actually released into - a mismatch produces certificates that are valid for names nothing answers on"

  validation {
    condition     = can(regex("^[a-z0-9]([-a-z0-9]*[a-z0-9])?$", var.namespace))
    error_message = "namespace must be a valid lowercase RFC 1123 label."
  }
}
variable "cluster_domain" {
  type        = string
  default     = "cluster.local"
  description = "Cluster DNS domain, matching the chart's clusterDomain value. Appended to the in-cluster SANs"

  validation {
    condition     = can(regex("^[a-z0-9]([-a-z0-9.]*[a-z0-9])?$", var.cluster_domain))
    error_message = "cluster_domain must be a valid lowercase DNS name."
  }
}
variable "external_dns_names" {
  type        = list(string)
  default     = []
  description = <<-DESC
    Names outside the cluster that this certificate must also be valid for - in practice the load balancer
    in front of the Karmada API server, because that is the address both the agents on the member clusters
    and the kubectl provider in this root connect to.

    This is the equivalent of the guidance installer's --cert-external-dns flag, which it set to
    "*.elb.<region>.amazonaws.com". That wildcard works for a Network Load Balancer because an NLB's name is
    <name>-<hash>.elb.<region>.amazonaws.com - one label under elb.<region>.amazonaws.com. It would not work
    for an ALB, whose name is <name>-<hash>.<region>.elb.amazonaws.com.
  DESC

  validation {
    condition     = alltrue([for name in var.external_dns_names : can(regex("^[*a-z0-9]([-a-z0-9.]*[a-z0-9])?$", name))])
    error_message = "external_dns_names must each be a DNS name, optionally with a leading wildcard label."
  }
}
variable "external_ip_addresses" {
  type        = list(string)
  default     = []
  description = "Addresses outside the cluster to add as IP SANs, the equivalent of the installer's --karmada-apiserver-advertise-address. Empty here: a load balancer is reached by name, and its addresses change. 127.0.0.1 is always included regardless"

  validation {
    condition     = alltrue([for address in var.external_ip_addresses : can(regex("^[0-9]+\\.[0-9]+\\.[0-9]+\\.[0-9]+$", address))])
    error_message = "external_ip_addresses must each be an IPv4 address."
  }
}
variable "ca_common_name" {
  type        = string
  default     = "karmada"
  description = "Common name of the server CA, as karmada init names it. Cosmetic - nothing validates it - but kept so a certificate chain printed from this control plane reads the same as one the installer produced"

  validation {
    condition     = length(var.ca_common_name) > 0
    error_message = "ca_common_name must not be empty."
  }
}
variable "client_common_name" {
  type        = string
  default     = "system:admin"
  description = "Common name of the karmada certificate, as karmada init sets it. This is the username the Karmada API server sees for anything presenting this certificate, so it appears in audit logs"

  validation {
    condition     = length(var.client_common_name) > 0
    error_message = "client_common_name must not be empty."
  }
}
variable "client_organization" {
  type        = string
  default     = "system:masters"
  description = "Organization of the karmada certificate, which Kubernetes reads as the client's group. A single string rather than a list, because the tls provider's subject block takes one organization - karmada init passes a slice of one here, so nothing is lost. It is not cosmetic: system:masters is the only thing granting this credential any permission at all on a Karmada API server running --authorization-mode=Node,RBAC, and there is no ClusterRoleBinding anywhere that would replace it"

  validation {
    condition     = var.client_organization == "system:masters"
    error_message = "client_organization must be system:masters. Without it the certificate authenticates and then cannot read anything, and the Karmada API server answers as if the cluster were empty rather than reporting a permissions problem - so the PropagationPolicy and the demo Deployment would fail with Forbidden against a control plane that looks healthy."
  }
}
variable "front_proxy_ca_common_name" {
  type        = string
  default     = "front-proxy-ca"
  description = "Common name of the aggregation layer's CA, as karmada init names it"

  validation {
    condition     = length(var.front_proxy_ca_common_name) > 0
    error_message = "front_proxy_ca_common_name must not be empty."
  }
}
variable "front_proxy_client_common_name" {
  type        = string
  default     = "front-proxy-client"
  description = "Common name of the aggregation layer's client certificate. Fixed by the apiserver's --requestheader-allowed-names flag, which the chart hardcodes to front-proxy-client, so this is the one subject here that is not a choice"

  validation {
    condition     = var.front_proxy_client_common_name == "front-proxy-client"
    error_message = "front_proxy_client_common_name must be front-proxy-client. The chart starts the Karmada API server with --requestheader-allowed-names=front-proxy-client hardcoded, so any other name makes the aggregation layer reject the proxy certificate - which surfaces only as the karmada-aggregated-apiserver's APIService going unavailable, with the rest of the control plane healthy."
  }
}
variable "rsa_bits" {
  type        = number
  default     = 3072
  description = "RSA key size, matching the chart's certs.auto.rsaSize. The karmada key doubles as the Karmada API server's service account signing key, so this is also the size of that"

  validation {
    condition     = contains([2048, 3072, 4096], var.rsa_bits)
    error_message = "rsa_bits must be 2048, 3072 or 4096."
  }
}
variable "validity_period_hours" {
  type        = number
  default     = 43800
  description = "Lifetime of the leaf certificates, matching the chart's certs.auto.expiry of 43800h (five years). Nothing rotates these: renewing means tainting this module's certificates and reinstalling the chart, which replaces the control plane"

  validation {
    condition     = var.validity_period_hours > 0
    error_message = "validity_period_hours must be positive."
  }
}
variable "ca_validity_period_hours" {
  type        = number
  default     = 87600
  description = "Lifetime of the two CAs, matching the chart's certs.auto.rootCAExpiryDays of 3650 days"

  validation {
    # The pair is what can be wrong: a leaf outliving its CA is a certificate that stops verifying before it
    # expires, and the chart's own values carry the same warning about expiry versus rootCAExpiryDays
    # (rules.md B-1).
    condition     = var.ca_validity_period_hours >= var.validity_period_hours
    error_message = "ca_validity_period_hours must be at least validity_period_hours. A leaf certificate that outlives the CA that signed it stops verifying on the CA's expiry rather than its own, and the failure appears as a TLS error from every client at once with no certificate visibly expired."
  }
}
