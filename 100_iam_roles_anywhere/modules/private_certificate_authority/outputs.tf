output "certificate_authority_arn" {
  value       = aws_acmpca_certificate_authority.private_ca.arn
  description = "ARN of the certificate authority. Both the trust anchor and the end-entity certificate name it, but neither can tell from this value whether the CA is usable - the ARN exists from the moment the CA is created, which is while it is still PENDING_CERTIFICATE"
}
output "certificate_authority_certificate" {
  value       = aws_acmpca_certificate.private_ca_certificate.certificate
  description = "The CA's self-signed certificate in PEM form. Public material - this is what a client validates an issued certificate against, and what a trust anchor configured with a certificate bundle rather than a CA ARN would be given. The CA's private key never leaves Private CA and is not retrievable at all"
}
output "certificate_authority_not_after" {
  value       = aws_acmpca_certificate_authority.private_ca.not_after
  description = "When the CA certificate expires. Anything it issued stops validating then, regardless of the end-entity certificate's own expiry"
}
# Terraform cannot answer whether the CA is ACTIVE: the activation resource has no status attribute
# to read, and the one thing that would report a problem - an issue request failing - happens in
# another module. So the check is handed over as a command (rules.md B-5).
output "status_command" {
  value       = "aws acm-pca describe-certificate-authority --certificate-authority-arn ${aws_acmpca_certificate_authority.private_ca.arn} --query 'CertificateAuthority.{Status:Status,Type:Type,NotAfter:NotAfter}'"
  description = "Whether the CA actually came up usable. ACTIVE is the expected answer. PENDING_CERTIFICATE means the activation did not take, and everything downstream of it will have failed; DISABLED means the enabled variable is false, in which case the CA bills but issues nothing"
}
