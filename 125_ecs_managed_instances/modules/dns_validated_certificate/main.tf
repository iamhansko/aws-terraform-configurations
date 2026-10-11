# An ACM certificate and the DNS records that validate it.
#
# The validation half is what the CloudFormation conversion lost. The original passed DomainValidationOptions
# with a hosted zone ID, which makes CloudFormation create the CNAME and wait for ISSUED by itself; the
# conversion kept validation_method = "DNS" and dropped the rest - the hosted zone parameter it took survived
# as a variable nothing read. The certificate would have sat in PENDING_VALIDATION, and the HTTPS listener
# that named it would have been rejected with UnsupportedCertificate.
resource "aws_acm_certificate" "certificate" {
  domain_name       = var.domain_name
  key_algorithm     = var.key_algorithm
  validation_method = "DNS"
  # A replacement - a new domain name, say - is issued before the old one is released, so the listener always
  # has a valid certificate to point at.
  lifecycle {
    create_before_destroy = true
  }
}
# for_each keyed by domain name. The keys come from domain_name, which is configuration, so they are known at
# plan even though the record names and values are not (rules.md B-8).
resource "aws_route53_record" "validation" {
  for_each = {
    for option in aws_acm_certificate.certificate.domain_validation_options : option.domain_name => {
      name  = option.resource_record_name
      type  = option.resource_record_type
      value = option.resource_record_value
    }
  }
  zone_id         = var.route53_zone_id
  name            = each.value.name
  type            = each.value.type
  records         = [each.value.value]
  ttl             = 60
  allow_overwrite = true
}
# Waits for ISSUED. Its certificate_arn is what consumers should reference, so they are ordered after the
# certificate is usable rather than after it merely exists.
resource "aws_acm_certificate_validation" "certificate" {
  certificate_arn         = aws_acm_certificate.certificate.arn
  validation_record_fqdns = [for record in aws_route53_record.validation : record.fqdn]
}
