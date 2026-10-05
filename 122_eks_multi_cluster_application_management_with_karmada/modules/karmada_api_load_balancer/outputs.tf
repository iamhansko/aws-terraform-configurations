output "endpoint" {
  value       = local.endpoint
  description = "The Karmada API server's address, as a URL. This is the single value the rest of the configuration is built around: the karmada certificate carries it as a SAN, each member cluster's agent connects to it, and the kubectl provider that creates the PropagationPolicy uses it as its host (rules.md B-5)"
}
output "dns_name" {
  value       = aws_lb.karmada_api.dns_name
  description = "DNS name of the load balancer, without scheme or port. Passed to the certificate module as an external SAN"
}
output "port" {
  value       = var.port
  description = "The listener port, which is also the Service nodePort the caller must pass to the chart as apiServer.nodePort. Re-exposed from the input so the two cannot drift (rules.md B-5)"
}
output "load_balancer_arn" {
  value       = aws_lb.karmada_api.arn
  description = "ARN of the load balancer"
}
output "target_group_arn" {
  value       = aws_lb_target_group.karmada_api.arn
  description = "ARN of the target group the parent cluster's Auto Scaling group is attached to"
}
output "target_health_command" {
  value       = "aws elbv2 describe-target-health --target-group-arn ${aws_lb_target_group.karmada_api.arn} --query 'TargetHealthDescriptions[].{Target:Target.Id,State:TargetHealth.State,Reason:TargetHealth.Reason}' --output table"
  description = "Health of every registered node. This is the first thing to read when the Karmada API server is unreachable but its pods are Running: all targets unhealthy means nothing is listening on the node port, which is the Service's nodePort not matching this module's port, or the chart having been installed with apiServer.serviceType left at ClusterIP"
}
output "endpoint_check_command" {
  # %%{ rather than %{ - Terraform reads %{ as the start of a template directive and rejects http_code as a
  # control keyword. Doubling the percent sign emits a literal one, which is what curl's -w format needs.
  value       = "curl -sk -o /dev/null -w '%%{http_code}\\n' ${local.endpoint}/readyz"
  description = "Whether the endpoint answers at all. 401 or 403 is the healthy answer - it means TLS completed and the API server rejected an unauthenticated request. A timeout is a target health or security group problem; a TLS error means the certificate does not carry this load balancer's name as a SAN"
}
