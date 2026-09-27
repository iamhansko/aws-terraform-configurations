output "pod_security_group_id" {
  value       = aws_security_group.default_pod_security_group.id
  description = "ID of the security group assigned to pods via SecurityGroupPolicy, for other modules (e.g. web_ec2) to reference as an ingress source"
}
