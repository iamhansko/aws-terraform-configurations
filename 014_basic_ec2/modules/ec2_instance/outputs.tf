output "instance_id" {
  value       = aws_instance.ec2.id
  description = "ID of the instance, for targeting SSM sessions and associations at it"
}
output "public_ip" {
  value       = aws_instance.ec2.public_ip
  description = "Public IP address of the instance, or empty when associate_public_ip_address is false"
}
output "private_ip" {
  value       = aws_instance.ec2.private_ip
  description = "Private IP address of the instance"
}
output "public_dns" {
  value       = aws_instance.ec2.public_dns
  description = "Public DNS name of the instance, or empty when it has no public IP"
}
output "security_group_id" {
  value       = aws_security_group.ec2_security_group.id
  description = "ID of the instance's security group, for another module to reference as an ingress source (rules.md B-8 - pass this into a map, not a list)"
}
output "iam_role_arn" {
  value       = length(var.iam_policy_arns) > 0 ? aws_iam_role.ec2_iam_role[0].arn : null
  description = "ARN of the instance's IAM role, or null when iam_policy_arns is empty and no role was created"
}
output "iam_role_name" {
  value       = length(var.iam_policy_arns) > 0 ? aws_iam_role.ec2_iam_role[0].name : null
  description = "Name of the instance's IAM role, for attaching extra policies from the root module, or null when no role was created"
}
