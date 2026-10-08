variable "certificate_authority_type" {
  type        = string
  default     = "ROOT"
  description = "Whether the CA signs its own certificate (ROOT) or is signed by another CA (SUBORDINATE). ROOT, as the _monolithic template had it. SUBORDINATE would need the parent's chain passed to the activation resource, which this module does not take"

  validation {
    condition     = contains(["ROOT", "SUBORDINATE"], var.certificate_authority_type)
    error_message = "certificate_authority_type must be ROOT or SUBORDINATE."
  }
  validation {
    # The activation resource here passes no certificate_chain, which only a self-signed root can
    # do. Catching it in plan rather than on MalformedCertificateException during apply.
    condition     = var.certificate_authority_type == "ROOT"
    error_message = "certificate_authority_type must be ROOT in this module, because the activation resource imports a self-signed certificate with no certificate_chain. A SUBORDINATE CA needs the parent chain passed alongside it, which this module has no variable for."
  }
}
variable "usage_mode" {
  type        = string
  default     = "GENERAL_PURPOSE"
  description = "GENERAL_PURPOSE issues certificates with any validity period; SHORT_LIVED_CERTIFICATE is cheaper per certificate but caps validity at 7 days. GENERAL_PURPOSE, as the _monolithic template had it - the certificate this CA issues is exported and then used by hand, so a 7 day ceiling would expire mid-demo"

  validation {
    condition     = contains(["GENERAL_PURPOSE", "SHORT_LIVED_CERTIFICATE"], var.usage_mode)
    error_message = "usage_mode must be GENERAL_PURPOSE or SHORT_LIVED_CERTIFICATE."
  }
}
variable "key_storage_security_standard" {
  type        = string
  default     = "FIPS_140_2_LEVEL_3_OR_HIGHER"
  description = "HSM class backing the CA key, as the _monolithic template had it. Not offered in every region - see main.tf for the error that produces and why the answer is level 2 rather than a retry"

  validation {
    condition     = contains(["FIPS_140_2_LEVEL_2_OR_HIGHER", "FIPS_140_2_LEVEL_3_OR_HIGHER"], var.key_storage_security_standard)
    error_message = "key_storage_security_standard must be FIPS_140_2_LEVEL_2_OR_HIGHER or FIPS_140_2_LEVEL_3_OR_HIGHER."
  }
}
variable "enabled" {
  type        = bool
  default     = true
  description = "Whether the CA is ACTIVE once its certificate is imported, or DISABLED. True reproduces the Status: ACTIVE the _monolithic template set on the activation. A DISABLED CA still bills and still reads as a valid trust anchor source, but issues nothing - so the end-entity certificate request fails and the export never happens"
}
variable "permanent_deletion_time_in_days" {
  type        = number
  default     = 7
  description = "Days a deleted CA remains restorable. 7 is the AWS minimum; 30 is the provider default the _monolithic template inherited. Shortened here because a demo CA is not worth keeping restorable, and because the CA is the one resource in this project that bills by the month"

  validation {
    condition     = var.permanent_deletion_time_in_days >= 7 && var.permanent_deletion_time_in_days <= 30
    error_message = "permanent_deletion_time_in_days must be between 7 and 30, the range AWS Private CA accepts."
  }
}
variable "key_algorithm" {
  type        = string
  default     = "RSA_2048"
  description = "Algorithm of the CA key pair, as the _monolithic template had it. RSA is not interchangeable with EC here: the credential test scripts compare the certificate and key moduli with openssl rsa, which only reads an RSA key"

  validation {
    condition     = contains(["RSA_2048", "RSA_4096", "EC_prime256v1", "EC_secp384r1"], var.key_algorithm)
    error_message = "key_algorithm must be one of RSA_2048, RSA_4096, EC_prime256v1, EC_secp384r1."
  }
}
variable "signing_algorithm" {
  type        = string
  default     = "SHA256WITHRSA"
  description = "Algorithm the CA signs with, used both for the CA configuration and for the self-signed certificate request. Must match the key family in key_algorithm - a SHA256WITHRSA signature cannot be produced by an EC key, and the mismatch is rejected at apply with InvalidArgsException"

  validation {
    condition = contains([
      "SHA256WITHRSA", "SHA384WITHRSA", "SHA512WITHRSA",
      "SHA256WITHECDSA", "SHA384WITHECDSA", "SHA512WITHECDSA",
    ], var.signing_algorithm)
    error_message = "signing_algorithm must be one of SHA256WITHRSA, SHA384WITHRSA, SHA512WITHRSA, SHA256WITHECDSA, SHA384WITHECDSA, SHA512WITHECDSA."
  }
  validation {
    # Cross-variable, because the constraint is about the pair rather than either value
    # (rules.md B-1). An RSA key cannot produce an ECDSA signature and the reverse.
    condition     = startswith(var.key_algorithm, "RSA_") == endswith(var.signing_algorithm, "WITHRSA")
    error_message = "signing_algorithm must be a WITHRSA algorithm when key_algorithm is RSA_*, and a WITHECDSA algorithm when it is EC_*. AWS Private CA rejects the mismatched pair with InvalidArgsException at apply time."
  }
}
variable "subject_organization" {
  type        = string
  default     = "Peccy Inc"
  description = "Organization in the CA's subject distinguished name, as the _monolithic template had it"

  validation {
    condition     = length(var.subject_organization) > 0 && length(var.subject_organization) <= 64
    error_message = "subject_organization must be 1-64 characters, the X.509 limit for the O attribute."
  }
}
variable "subject_organizational_unit" {
  type        = string
  default     = "Red Team"
  description = "Organizational unit in the CA's subject distinguished name, as the _monolithic template had it"

  validation {
    condition     = length(var.subject_organizational_unit) > 0 && length(var.subject_organizational_unit) <= 64
    error_message = "subject_organizational_unit must be 1-64 characters, the X.509 limit for the OU attribute."
  }
}
variable "subject_country" {
  type        = string
  default     = "KR"
  description = "Two letter country code in the CA's subject distinguished name, as the _monolithic template had it"

  validation {
    condition     = can(regex("^[A-Z]{2}$", var.subject_country))
    error_message = "subject_country must be a two letter uppercase ISO 3166-1 alpha-2 code (e.g. KR)."
  }
}
variable "root_certificate_template_arn" {
  type        = string
  default     = "arn:aws:acm-pca:::template/RootCACertificate/V1"
  description = "Certificate template the self-signed CA certificate is issued against, as the _monolithic template had it. An end-entity template here produces a certificate without CA basic constraints, and importing that fails rather than producing a CA that silently cannot sign"

  validation {
    condition     = can(regex("^arn:aws[a-z-]*:acm-pca:::template/", var.root_certificate_template_arn))
    error_message = "root_certificate_template_arn must be an AWS Private CA template ARN (e.g. arn:aws:acm-pca:::template/RootCACertificate/V1)."
  }
}
variable "certificate_validity_type" {
  type        = string
  default     = "YEARS"
  description = "Unit of the CA certificate's validity period, as the _monolithic template had it"

  validation {
    condition     = contains(["DAYS", "MONTHS", "YEARS", "ABSOLUTE", "END_DATE"], var.certificate_validity_type)
    error_message = "certificate_validity_type must be one of DAYS, MONTHS, YEARS, ABSOLUTE, END_DATE."
  }
}
variable "certificate_validity_value" {
  type        = number
  default     = 10
  description = "Length of the CA certificate's validity period in certificate_validity_type units, as the _monolithic template had it. It has to outlast any certificate the CA issues: an end-entity certificate valid past its issuer's own expiry is issued without complaint and then fails validation"

  validation {
    condition     = var.certificate_validity_value > 0
    error_message = "certificate_validity_value must be greater than zero."
  }
}
variable "permission_actions" {
  type        = list(string)
  default     = ["IssueCertificate", "GetCertificate", "ListPermissions"]
  description = "Private CA actions granted to permission_principal, as the _monolithic template had it. IssueCertificate is the one that matters - without it ACM cannot request the end-entity certificate at all. GetCertificate lets ACM retrieve the issued body, and ListPermissions lets it confirm the grant"

  validation {
    condition = length(var.permission_actions) > 0 && alltrue([
      for action in var.permission_actions : contains(["IssueCertificate", "GetCertificate", "ListPermissions"], action)
    ])
    error_message = "permission_actions must be a non-empty subset of IssueCertificate, GetCertificate, ListPermissions - the only actions a Private CA permission accepts."
  }
  validation {
    condition     = contains(var.permission_actions, "IssueCertificate")
    error_message = "permission_actions must include IssueCertificate, because the whole point of this grant is to let ACM issue the end-entity certificate from this CA. Without it the certificate request fails with a ValidationException naming ACM rather than this permission."
  }
}
variable "permission_principal" {
  type        = string
  default     = "acm.amazonaws.com"
  description = "Service principal the permission is granted to, as the _monolithic template had it. acm.amazonaws.com, because it is ACM - not the operator running terraform - that calls IssueCertificate when an aws_acm_certificate names a private CA"

  validation {
    condition     = can(regex("^[a-z0-9.-]+\\.amazonaws\\.com$", var.permission_principal))
    error_message = "permission_principal must be an AWS service principal (e.g. acm.amazonaws.com)."
  }
}
