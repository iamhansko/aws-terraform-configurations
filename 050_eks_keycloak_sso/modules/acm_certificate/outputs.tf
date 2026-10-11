# The validated ARN, not the certificate's own. Referencing aws_acm_certificate_validation rather
# than aws_acm_certificate is what makes every consumer wait for validation to finish - the two
# attributes hold the same string, so the only difference is the dependency edge, and that edge is
# the whole point of this module (rules.md D-1).
output "certificate_arn" {
  value       = aws_acm_certificate_validation.certificate.certificate_arn
  description = "ARN of the validated certificate. Deliberately taken from the validation resource so that anything attaching it is ordered after ACM has issued it - the _monolithic template attached the unvalidated ARN, which cannot serve traffic"
}
output "domain_name" {
  value       = aws_acm_certificate.certificate.domain_name
  description = "Name the certificate was issued for, re-exposed so the Ingress host and the certificate cannot name different domains (rules.md B-5)"
}
output "status" {
  value       = aws_acm_certificate.certificate.status
  description = "Certificate status. ISSUED once validation has completed; PENDING_VALIDATION here after a successful apply would mean the validation records went into a zone nothing resolves"
}
output "validation_record_fqdns" {
  value       = [for record in aws_route53_record.validation : record.fqdn]
  description = "The validation CNAMEs this module created. Worth surfacing when validation times out: these are the names ACM is looking for, so they can be checked with dig against the public resolvers rather than only in the console"
}
output "status_command" {
  value       = "aws acm describe-certificate --certificate-arn ${aws_acm_certificate.certificate.arn} --query 'Certificate.[Status,DomainValidationOptions[].ValidationStatus]' --output text"
  description = "Command showing the certificate's status and each name's validation state"
}
