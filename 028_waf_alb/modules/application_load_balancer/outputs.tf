output "arn" {
  value       = aws_lb.load_balancer.arn
  description = "ARN of the load balancer. This is the resource ARN the web ACL association takes, and the reference is what orders the association after the load balancer exists"
}
output "name" {
  value       = aws_lb.load_balancer.name
  description = "Name of the load balancer, generated when the caller passed name as null"
}
output "dns_name" {
  value       = aws_lb.load_balancer.dns_name
  description = "Hostname the load balancer answers on"
}
output "zone_id" {
  value       = aws_lb.load_balancer.zone_id
  description = "Hosted zone id of the load balancer, for a Route 53 alias record pointing a domain at it"
}
output "url" {
  value       = local.url
  description = "The endpoint the demo sends its requests to. http, because the listener is HTTP - which costs the demo nothing, since the web ACL inspects requests after the listener has terminated them"
}
output "security_group_id" {
  value       = aws_security_group.load_balancer_security_group.id
  description = "ID of the frontend security group. The app server's module takes this as the source of its ingress rule, and because it is another module's output it has to arrive there as a map value with a static key rather than in a list (rules.md B-8)"
}
output "target_group_arn" {
  value       = aws_lb_target_group.target_group.arn
  description = "ARN of the target group. The root registers the app server against this, which is the one resource joining this module to the instance module (rules.md C-1)"
}
output "target_group_name" {
  value       = aws_lb_target_group.target_group.name
  description = "Name of the target group, generated when the caller passed target_group_name as null"
}
output "target_port" {
  value       = var.target_port
  description = "Port the target group expects targets to listen on, handed straight back out so the root's registration cannot name a different port than the target group was created with (rules.md B-5). A registration on the wrong port is accepted by the API and then fails every health check"
}
output "listener_arn" {
  value       = aws_lb_listener.listener.arn
  description = "ARN of the HTTP listener. A load balancer with no listener accepts nothing, which is also why the web ACL association is ordered after this whole module rather than after the load balancer alone"
}
output "listener_port" {
  value       = var.listener_port
  description = "Port the listener binds, re-exposed so a caller building a URL or a security group rule reads the same number the listener was created with (rules.md B-5)"
}
output "target_health_command" {
  value       = local.target_health_command
  description = "State of every registered target. This is the first thing to run when the demo URL answers 503: unhealthy with reason Target.Timeout points at the security groups, Target.FailedHealthChecks at the app or the health check path, and an empty table means nothing was ever registered"
}
