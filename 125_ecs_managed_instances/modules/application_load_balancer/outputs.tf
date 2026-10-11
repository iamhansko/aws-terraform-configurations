output "dns_name" {
  value       = aws_lb.load_balancer.dns_name
  description = "DNS name of the ALB"
}
output "zone_id" {
  value       = aws_lb.load_balancer.zone_id
  description = "Route 53 zone ID of the ALB, for an alias record"
}
output "url" {
  value       = "${var.enable_https ? "https" : "http"}://${aws_lb.load_balancer.dns_name}"
  description = "URL the ALB answers on directly. With a certificate this fails the TLS name check - the certificate names the custom domain, not this host"
}
output "security_group_id" {
  value       = aws_security_group.load_balancer.id
  description = "ID of the ALB's security group, for the service's security group to accept traffic from"
}
output "target_group_arn" {
  value       = aws_lb_target_group.target_group.arn
  description = "ARN of the target group. Read from listener_ready instead when ordering a service after the listener"
}
output "listener_ready" {
  value       = concat([for listener in aws_lb_listener.https : listener.arn], [aws_lb_listener.http.arn])
  description = "ARNs of the listeners. ECS rejects a service whose target group is not yet attached to a load balancer, and target_group_arn alone does not order a service after the listener that attaches it"
}
output "target_port" {
  value       = var.target_port
  description = "Port the targets listen on (rules.md B-5)"
}
output "target_health_command" {
  value       = "aws elbv2 describe-target-health --target-group-arn ${aws_lb_target_group.target_group.arn} --query 'TargetHealthDescriptions[].[Target.Id,Target.AvailabilityZone,TargetHealth.State,TargetHealth.Reason]' --output table"
  description = "Whether the ALB can reach the tasks. Target.Timeout is a security group path problem, not an application one"
}
