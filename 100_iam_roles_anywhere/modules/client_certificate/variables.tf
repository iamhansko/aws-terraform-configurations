variable "certificate_authority_arn" {
  type        = string
  description = "ARN of the private CA that issues this certificate. Injected rather than looked up here, so this module does not need to know how the CA was built (rules.md B-6). Note that a well-formed ARN says nothing about whether the CA is ACTIVE, which is why the caller also orders this module after the whole CA module"

  validation {
    condition     = can(regex("^arn:aws[a-z-]*:acm-pca:", var.certificate_authority_arn))
    error_message = "certificate_authority_arn must be an AWS Private CA certificate authority ARN (e.g. arn:aws:acm-pca:ap-northeast-2:111122223333:certificate-authority/...)."
  }
}
variable "domain_name" {
  type        = string
  default     = "rolesanywhere.com"
  description = "Subject common name of the issued certificate, as the _monolithic template had it. Nothing resolves it: a certificate used as an IAM Roles Anywhere credential is matched by its issuer and its subject is only an identifier, so this does not have to be a domain anyone owns"

  validation {
    condition     = can(regex("^[a-zA-Z0-9*]([a-zA-Z0-9.-]{0,251}[a-zA-Z0-9])?$", var.domain_name))
    error_message = "domain_name must be a DNS-shaped name of at most 253 characters, which is the form ACM accepts for a certificate subject."
  }
}
variable "key_algorithm" {
  type        = string
  default     = "RSA_2048"
  description = "Key algorithm of the issued certificate, as the _monolithic template had it. It has to stay RSA for this project: the credential helper is given the exported key directly, and the test scripts prove the key belongs to the certificate with openssl rsa, which reads RSA keys only"

  validation {
    condition     = contains(["RSA_1024", "RSA_2048", "EC_prime256v1", "EC_secp384r1", "EC_secp521r1"], var.key_algorithm)
    error_message = "key_algorithm must be one of RSA_1024, RSA_2048, EC_prime256v1, EC_secp384r1, EC_secp521r1."
  }
}
