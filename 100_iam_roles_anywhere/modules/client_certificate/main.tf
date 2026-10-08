# The end-entity certificate that stands in for the on-premises server's identity. One ACM
# certificate, issued by the private CA rather than by a public ACM authority.
#
# That distinction is the project. A public ACM certificate cannot be exported - ExportCertificate
# returns ValidationException for one, and the private key is never available to the caller - so
# the bootstrap in certificate_export_ec2 could not retrieve anything to hand IAM Roles Anywhere.
# A certificate issued by a private CA can be exported, key included, which is what makes a
# certificate usable as a credential outside AWS.
#
# Separate from the private_certificate_authority module rather than folded into it, because the
# two have different lifecycles and the boundary is where an ordering constraint lives. The CA is
# the trust root the trust anchor registers once; this is one credential issued from it, and a
# deployment handing certificates to several servers would have several of these and still one CA.
# More practically, this resource cannot be created until the CA is ACTIVE *and* ACM has been
# granted IssueCertificate on it, and the only place that can be expressed is a depends_on between
# modules - see the root main.tf (rules.md D-2).
resource "aws_acm_certificate" "client_certificate" {
  certificate_authority_arn = var.certificate_authority_arn
  domain_name               = var.domain_name
  key_algorithm             = var.key_algorithm

  # No validation_method and no validation records, which is right for a private certificate and
  # would be an omission for a public one: the issuing CA is already trusted by whoever trusts the
  # CA, so there is no domain ownership to prove. domain_name is a name in the certificate's
  # subject, not a DNS record that has to resolve - rolesanywhere.com is never looked up.

  lifecycle {
    # ACM cannot change a certificate's subject, so a new domain_name is a new certificate. Create
    # it before destroying the old one: the bootstrap exports by ARN, and a window with no
    # certificate is a window in which that export returns ResourceNotFoundException.
    create_before_destroy = true
  }
}
