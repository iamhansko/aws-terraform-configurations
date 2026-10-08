# The trust root of the whole project: a ROOT certificate authority in AWS Private CA, the
# certificate that activates it, and the grant that lets ACM issue from it.
#
# Four resources rather than one, and the reason is the lifecycle of a CA rather than a preference.
# CreateCertificateAuthority returns a CA in PENDING_CERTIFICATE: it has a key pair and a signing
# request and no certificate, so it can sign nothing. For a ROOT CA the missing certificate is one
# it signs for itself, which is a round trip - issue from the CSR, then import the result back.
# That round trip is aws_acmpca_certificate followed by
# aws_acmpca_certificate_authority_certificate, and only when the second one succeeds does the CA
# leave PENDING_CERTIFICATE.
#
# Everything downstream waits on that, which is why this is its own module: the trust anchor and
# the end-entity certificate both need an ACTIVE CA, and neither of them can tell by looking at a
# value. See the depends_on comments in the root main.tf (rules.md D-2).
#
# Cost, because it is unusual for this repository: a CA in AWS Private CA is billed per month from
# the moment it is created, whether or not it ever issues anything, and deleting it is the only
# thing that stops that. It is the reason this project is not left applied.
resource "aws_acmpca_certificate_authority" "private_ca" {
  type       = var.certificate_authority_type
  usage_mode = var.usage_mode
  # Which HSM class backs the CA key. The _monolithic template asked for level 3, which is the
  # provider default and available in most regions but not all of them - where it is not, the
  # create call fails with
  #
  #   InvalidArgsException: The specified key storage security standard is not supported in this
  #   region
  #
  # and the fix is FIPS_140_2_LEVEL_2_OR_HIGHER, not a retry.
  key_storage_security_standard = var.key_storage_security_standard
  # Whether the CA is usable once it has a certificate. The _monolithic template expressed this as
  # Status: ACTIVE on AWS::ACMPCA::CertificateAuthorityActivation, which has no Terraform
  # counterpart - see the comment on the activation resource below.
  enabled = var.enabled
  # How long a deleted CA stays restorable. 30 is the provider default and what the _monolithic
  # template inherited; 7 is the AWS minimum and what this sets, because nothing in a demo wants to
  # restore a throwaway CA and the shorter window is the one that lets the account be cleaned up.
  permanent_deletion_time_in_days = var.permanent_deletion_time_in_days
  certificate_authority_configuration {
    key_algorithm     = var.key_algorithm
    signing_algorithm = var.signing_algorithm
    subject {
      organization        = var.subject_organization
      organizational_unit = var.subject_organizational_unit
      country             = var.subject_country
    }
  }
}
# The CA signing its own certificate. template_arn is what makes it a root: RootCACertificate/V1
# asks Private CA to produce a self-signed CA certificate from the CSR above, with the basic
# constraints a CA needs. Issuing against an end-entity template here would produce a certificate
# the CA cannot use to sign anything, and the import below would be rejected.
resource "aws_acmpca_certificate" "private_ca_certificate" {
  certificate_authority_arn   = aws_acmpca_certificate_authority.private_ca.arn
  certificate_signing_request = aws_acmpca_certificate_authority.private_ca.certificate_signing_request
  signing_algorithm           = var.signing_algorithm
  template_arn                = var.root_certificate_template_arn
  validity {
    type  = var.certificate_validity_type
    value = var.certificate_validity_value
  }
}
# Importing the certificate is what activates the CA, and this resource is the import.
#
# AWS::ACMPCA::CertificateAuthorityActivation carried Status: ACTIVE and there is no attribute here
# to carry it to, which reads like something the conversion lost. It is not: the import itself is
# what moves the CA out of PENDING_CERTIFICATE, and whether it then lands on ACTIVE or DISABLED
# follows the enabled argument on the CA above. Nothing is missing.
#
# No certificate_chain argument, which is correct only because this is a ROOT CA - a self-signed
# certificate is its own chain. A SUBORDINATE CA has to pass the parent's chain here, and omitting
# it there fails with MalformedCertificateException.
resource "aws_acmpca_certificate_authority_certificate" "private_ca_activation" {
  certificate_authority_arn = aws_acmpca_certificate_authority.private_ca.arn
  certificate               = aws_acmpca_certificate.private_ca_certificate.certificate
}
# What lets ACM issue end-entity certificates from this CA on the caller's behalf.
#
# This is easy to read as audit decoration and it is not. aws_acm_certificate with a
# certificate_authority_arn does not call Private CA as the operator; ACM calls IssueCertificate as
# the acm.amazonaws.com service principal, and a CA grants that per principal. Without this
# resource the certificate request fails, and the message names ACM rather than this grant:
#
#   ValidationException: The ACM Private CA ... is not authorized to issue certificates on behalf
#   of ACM
#
# The client_certificate module therefore waits for this whole module, not just for the CA ARN
# (rules.md D-2).
resource "aws_acmpca_permission" "private_ca_permission" {
  certificate_authority_arn = aws_acmpca_certificate_authority.private_ca.arn
  actions                   = var.permission_actions
  principal                 = var.permission_principal
}
