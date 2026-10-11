variable "domain_name" {
  type        = string
  description = "The host name the certificate is issued for, e.g. shlink.example.com"

  validation {
    condition     = can(regex("^([a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?\\.)+[a-z]{2,}$", var.domain_name))
    error_message = "domain_name must be a lowercase DNS host name such as shlink.example.com."
  }
}
variable "route53_zone_id" {
  type        = string
  description = "Public hosted zone the validation records are written to. It has to be the zone the domain actually delegates to - records in an undelegated zone are never seen, and the validation waits until it times out"

  validation {
    condition     = can(regex("^Z[A-Z0-9]+$", var.route53_zone_id))
    error_message = "route53_zone_id must be a Route 53 hosted zone ID (e.g. Z0123456789ABCDEFGHIJ)."
  }
}
variable "key_algorithm" {
  type        = string
  default     = "RSA_2048"
  description = "Key algorithm of the certificate, as the _monolithic template had it"

  validation {
    condition     = contains(["RSA_2048", "EC_prime256v1", "EC_secp384r1"], var.key_algorithm)
    error_message = "key_algorithm must be RSA_2048, EC_prime256v1 or EC_secp384r1 - the algorithms ACM issues DNS-validated certificates with."
  }
}
