output "security_group_id" {
  value       = aws_security_group.bastion_ec2_security_group.id
  description = "ID of the bastion EC2 instance's security group"
}

output "instance_id" {
  value       = aws_instance.bastion_ec2.id
  description = "ID of the bastion EC2 instance"
}
