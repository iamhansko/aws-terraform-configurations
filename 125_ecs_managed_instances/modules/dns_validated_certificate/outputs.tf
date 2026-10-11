output "certificate_arn" {
  value       = aws_acm_certificate_validation.certificate.certificate_arn
  description = "ARN of the certificate, read from the validation resource so a listener referencing it waits for ISSUED"
}
output "domain_name" {
  value       = aws_acm_certificate.certificate.domain_name
  description = "The host name the certificate covers (rules.md B-5)"
}
output "status_command" {
  value       = "aws acm describe-certificate --certificate-arn ${aws_acm_certificate.certificate.arn} --query 'Certificate.[Status,DomainValidationOptions[0].ValidationStatus]' --output table"
  description = "Whether the certificate was issued. PENDING_VALIDATION that never moves means the hosted zone is not the one the domain is delegated to"
}
