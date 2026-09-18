output "cloudwatch_observability_addon_arn" {
  value       = aws_eks_addon.cloudwatch_observability.arn
  description = "ARN of the amazon-cloudwatch-observability EKS addon"
}
output "log_group_name" {
  value       = "/aws/eks/${var.cluster_name}/node-monitoring-agent"
  description = "Log group the Fluent Bit OUTPUT block writes the Node Monitoring Agent's records to. Created by Fluent Bit on the first record because auto_create_group is on, so it does not exist until the agent has logged something"
}
output "log_tail_command" {
  value       = "aws logs tail /aws/eks/${var.cluster_name}/node-monitoring-agent --follow"
  description = "Command following the agent's log for this cluster. This is where the detected condition appears without kubectl (rules.md H-2)"
}
