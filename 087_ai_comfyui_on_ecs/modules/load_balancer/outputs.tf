output "arn" {
  value       = aws_lb.alb.arn
  description = "ARN of the load balancer, which the web ACL is associated with"
}
output "dns_name" {
  value       = aws_lb.alb.dns_name
  description = "DNS name of the load balancer - the blueprint's Endpoint output"
}
output "url" {
  value       = "https://${lower(aws_lb.alb.dns_name)}"
  description = "HTTPS address of the load balancer, lowercased. The lowercase form is the one a browser sends and the one the Cognito callback URLs are registered with (modules/cognito_user_pool)"
}
output "security_group_id" {
  value       = aws_security_group.alb.id
  description = "Security group of the load balancer, which the ComfyUI task admits on its port"
}
output "https_listener_arn" {
  value       = aws_lb_listener.https.arn
  description = "ARN of the HTTPS listener the authenticated rules are attached to"
}
output "target_group_arn" {
  value       = aws_lb_target_group.comfyui.arn
  description = "ARN of the target group the ComfyUI task registers in"
}
output "target_group_arn_suffix" {
  value       = aws_lb_target_group.comfyui.arn_suffix
  description = "The target group's CloudWatch dimension value, for reading its HealthyHostCount"
}
output "load_balancer_arn_suffix" {
  value       = aws_lb.alb.arn_suffix
  description = "The load balancer's CloudWatch dimension value"
}
output "certificate_arn" {
  value       = aws_acm_certificate.certificate.arn
  description = "ARN of the imported self-signed certificate"
}
output "certificate_expires_at" {
  value       = tls_self_signed_cert.certificate.validity_end_time
  description = "When the self-signed certificate expires. The first apply after this date issues a new one"
}
