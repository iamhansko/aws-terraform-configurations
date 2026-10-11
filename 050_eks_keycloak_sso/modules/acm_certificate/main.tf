# An ACM certificate that is actually usable, which means validated.
#
# The _monolithic template created the certificate and stopped there:
#
#   resource "aws_acm_certificate" "acm_certificate" {
#     domain_name       = "keycloak.${var.keycloak_domain}"
#     validation_method = "DNS"
#   }
#
# DNS validation does nothing on its own - ACM publishes a CNAME it expects to find in the zone,
# and until that record exists the certificate stays PENDING_VALIDATION forever. A pending
# certificate attached to an ALB listener serves nothing usable, so the https URL the template
# printed as an output could not work. Terraform reported success the whole time, because creating
# a certificate and validating one are different operations.
#
# This module does all three parts: the certificate, the validation records in the zone, and the
# wait for ACM to notice them. Anything that consumes certificate_arn from here is therefore
# ordered after validation completes.
resource "aws_acm_certificate" "certificate" {
  domain_name               = var.domain_name
  subject_alternative_names = var.subject_alternative_names
  key_algorithm             = var.key_algorithm
  validation_method         = "DNS"

  tags = merge({ Name = var.domain_name }, var.tags)

  lifecycle {
    # ACM will not let a certificate in use be deleted, so a change that forces replacement has to
    # create the new one before the old one is detached.
    create_before_destroy = true
  }
}
# One record per name ACM asks about - the certificate plus any subject alternative names. Keyed by
# domain rather than by index so adding a SAN does not renumber the existing records.
#
# for_each over a resource attribute is safe here because domain_validation_options is known once
# the certificate exists, and the certificate is created before these are planned in the same apply;
# the keys come from var.domain_name and var.subject_alternative_names, which are configuration
# (rules.md B-8).
resource "aws_route53_record" "validation" {
  for_each = {
    for option in aws_acm_certificate.certificate.domain_validation_options :
    option.domain_name => option
  }

  zone_id = var.zone_id
  name    = each.value.resource_record_name
  type    = each.value.resource_record_type
  records = [each.value.resource_record_value]
  ttl     = var.validation_record_ttl
  # ACM reissues the same validation CNAME for a certificate that is replaced, and a stale record
  # with the same name would otherwise block the new one.
  allow_overwrite = true
}
# The wait. Without it, anything referencing the certificate ARN can attach it while it is still
# PENDING_VALIDATION - which is exactly what the _monolithic template did.
resource "aws_acm_certificate_validation" "certificate" {
  certificate_arn         = aws_acm_certificate.certificate.arn
  validation_record_fqdns = [for record in aws_route53_record.validation : record.fqdn]

  timeouts {
    create = var.validation_timeout
  }
}
