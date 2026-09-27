output "private_ip" {
  value       = aws_instance.web_ec2.private_ip
  description = "Private IP address of the web EC2 instance"
}

output "security_group_id" {
  value       = aws_security_group.web_ec2_security_group.id
  description = "ID of the web EC2 instance's security group"
}
