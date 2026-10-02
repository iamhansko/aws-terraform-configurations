output "role_name" {
  value       = aws_iam_role.spot_interrupter_role.name
  description = "Name of the role, which the CLI looks up by name rather than being told"
}
output "role_arn" {
  value       = aws_iam_role.spot_interrupter_role.arn
  description = "ARN of the role. The CLI prints this in its experiment summary, which is the quickest confirmation that it found this role rather than creating one of its own"
}
output "interrupt_command" {
  value       = "ec2-spot-interrupter --delay ${var.interrupt_delay} --instance-ids <spot-instance-id>"
  description = "Sends a rebalance recommendation immediately and the two-minute interruption notice after the delay. Run it against an instance ID from the node list - the tool builds a FIS template, runs it and deletes it again, so nothing is left behind to inspect afterwards"
}
output "list_spot_instances_command" {
  value       = "aws ec2 describe-instances --filters Name=instance-lifecycle,Values=spot Name=instance-state-name,Values=running --query 'Reservations[].Instances[].{Id:InstanceId,Type:InstanceType,Name:Tags[?Key==`Name`]|[0].Value}' --output table"
  description = "The spot instances available to interrupt, with the Name tag that says which node group or pool each belongs to. The CLI takes instance IDs, so this is how to get one"
}
