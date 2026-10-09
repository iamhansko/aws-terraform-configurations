output "load_balancer_arn" {
  value       = aws_lb.application_load_balancer.arn
  description = "ARN of the application load balancer. This is the target the root registers in the app network load balancer's alb-type target group"
}
output "load_balancer_arn_suffix" {
  value       = aws_lb.application_load_balancer.arn_suffix
  description = "The app/<name>/<id> suffix, which is the LoadBalancer dimension value for every AWS/ApplicationELB metric. The dashboard and both alarms are built from it"
}
output "dns_name" {
  value       = aws_lb.application_load_balancer.dns_name
  description = "DNS name of the load balancer. Internal, so it resolves to private addresses and is only reachable from inside the VPCs or across the peering connection"
}
output "listener_arn" {
  value       = aws_lb_listener.application_load_balancer_listener.arn
  description = "ARN of the HTTP listener. Each application stack attaches its forwarding rules to this, and each CodeDeploy deployment group names it as the production traffic route (rules.md B-6)"
}
output "listener_port" {
  value       = aws_lb_listener.application_load_balancer_listener.port
  description = "Port of the HTTP listener, read from the listener resource rather than echoed from the input. The root registers this load balancer in an alb-type target group on this port, and elbv2 accepts that only once a listener on the port exists - taking the value from the listener is what orders the registration after it"
}
output "security_group_id" {
  value       = aws_security_group.application_load_balancer_security_group.id
  description = "The load balancer security group, named as an allowed source on the ECS service group"
}
output "listener_rules_command" {
  value       = "aws elbv2 describe-rules --listener-arn ${aws_lb_listener.application_load_balancer_listener.arn} --query 'Rules[].[Priority,Conditions[0].Values,Actions[0].TargetGroupArn,Actions[0].ForwardConfig.TargetGroups]' --output json"
  description = "Command printing every rule on this listener with the target group it forwards to. This is where a blue/green switch is visible: CodeDeploy rewrites the forward action of a stack's rule from the live target group to the other one, and nothing in Terraform state changes"
}
