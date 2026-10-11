variable "domain_name" {
  type        = string
  description = "Fully qualified name the certificate is issued for, e.g. keycloak.example.com. Must sit inside the hosted zone the validation records go into, or ACM publishes a CNAME this module cannot create and validation never completes"

  validation {
    condition     = can(regex("^([a-z0-9*]([-a-z0-9]*[a-z0-9])?\\.)+[a-z]{2,}$", var.domain_name))
    error_message = "domain_name must be a fully qualified lowercase domain name such as keycloak.example.com."
  }
}
variable "zone_id" {
  type        = string
  description = "Route 53 hosted zone the validation records are created in. Injected as an ID rather than looked up here, so this module never learns which zone it belongs to (rules.md B-6)"

  validation {
    condition     = can(regex("^Z[A-Z0-9]+$", var.zone_id))
    error_message = "zone_id must be a Route 53 hosted zone ID such as Z0123456789ABCDEFGHIJ."
  }
}
variable "subject_alternative_names" {
  type        = list(string)
  default     = []
  description = "Extra names on the certificate. Each one gets its own validation record, so the zone has to be authoritative for all of them"

  validation {
    condition     = alltrue([for name in var.subject_alternative_names : can(regex("^([a-z0-9*]([-a-z0-9]*[a-z0-9])?\\.)+[a-z]{2,}$", name))])
    error_message = "subject_alternative_names must all be fully qualified lowercase domain names."
  }
}
variable "key_algorithm" {
  type        = string
  default     = "RSA_2048"
  description = "Key algorithm for the certificate, RSA_2048 as the _monolithic template had it"

  validation {
    condition     = contains(["RSA_1024", "RSA_2048", "RSA_3072", "RSA_4096", "EC_prime256v1", "EC_secp384r1", "EC_secp521r1"], var.key_algorithm)
    error_message = "key_algorithm must be one of the algorithms ACM supports: RSA_1024, RSA_2048, RSA_3072, RSA_4096, EC_prime256v1, EC_secp384r1, EC_secp521r1."
  }
}
variable "validation_record_ttl" {
  type        = number
  default     = 60
  description = "TTL on the validation CNAMEs. Short, because they only matter until ACM has seen them once"

  validation {
    condition     = var.validation_record_ttl >= 0
    error_message = "validation_record_ttl must not be negative."
  }
}
variable "validation_timeout" {
  type        = string
  default     = "30m"
  description = "How long to wait for ACM to validate. Usually a couple of minutes; a timeout here almost always means the hosted zone is not the one actually serving the domain, so the CNAME is published where no resolver looks"

  validation {
    condition     = can(regex("^[0-9]+[smh]$", var.validation_timeout))
    error_message = "validation_timeout must be a Go duration such as 30m."
  }
}
variable "tags" {
  type        = map(string)
  default     = {}
  description = "Extra tags merged onto the certificate"
}
