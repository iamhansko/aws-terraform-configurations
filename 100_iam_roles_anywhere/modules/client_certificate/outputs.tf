output "certificate_arn" {
  value       = aws_acm_certificate.client_certificate.arn
  description = "ARN of the issued certificate. The bootstrap passes exactly this to aws acm export-certificate"
}
output "domain_name" {
  value       = aws_acm_certificate.client_certificate.domain_name
  description = "Subject common name the certificate was issued with, read back from ACM rather than echoed from the input so an output always reflects what exists (rules.md B-5)"
}
output "certificate_authority_arn" {
  value       = var.certificate_authority_arn
  description = "The CA this certificate was issued by, handed back so a caller can confirm the certificate and the trust anchor point at the same authority without holding the value twice (rules.md B-5). A certificate from a different CA is rejected by CreateSession, which reports only that the certificate is untrusted"
}
output "status_command" {
  value       = "aws acm describe-certificate --certificate-arn ${aws_acm_certificate.client_certificate.arn} --query 'Certificate.{Status:Status,Type:Type,NotAfter:NotAfter,CA:CertificateAuthorityArn}'"
  description = "Whether ACM actually issued the certificate. ISSUED and Type PRIVATE are expected. PENDING_VALIDATION would mean this was created as a public certificate, which cannot be exported - the export step would then fail and the apply would stop at the terminator Lambda's wait"
}
