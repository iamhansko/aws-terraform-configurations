output "arn" {
  value       = aws_lb.synced_load_balancer.arn
  description = "ARN of the pre-created load balancer"
}
output "name" {
  value       = aws_lb.synced_load_balancer.name
  description = "Name of the pre-created load balancer"
}
output "dns_name" {
  value       = aws_lb.synced_load_balancer.dns_name
  description = "DNS name of the pre-created load balancer, known from Terraform state before the controller has reconciled the workload"
}
output "url" {
  value       = "http://${aws_lb.synced_load_balancer.dns_name}"
  description = "HTTP URL of the pre-created load balancer"
}
output "zone_id" {
  value       = aws_lb.synced_load_balancer.zone_id
  description = "Hosted zone ID of the load balancer, for a Route 53 alias record"
}
output "stack" {
  value       = var.stack
  description = "The <namespace>/<name> stack tag this load balancer was tagged with, re-exposed so a mismatch with the workload is visible in outputs (rules.md B-5)"
}
