output "instance_id" {
  value       = aws_instance.vscode_ec2.id
  description = "ID of the VS Code EC2 instance"
}

output "public_ip" {
  value       = aws_instance.vscode_ec2.public_ip
  description = "Public IP address of the VS Code EC2 instance"
}

output "iam_role_arn" {
  value       = aws_iam_role.vscode_ec2_iam_role.arn
  description = "ARN of the VS Code EC2 instance's IAM role"
}

output "iam_role_name" {
  value       = aws_iam_role.vscode_ec2_iam_role.name
  description = "Name of the VS Code EC2 instance's IAM role"
}

output "security_group_id" {
  value       = aws_security_group.vscode_ec2_security_group.id
  description = "ID of the VS Code EC2 instance's security group"
}

output "marker_file_path" {
  value       = var.marker_file_path
  description = "Directory where the userdata completion marker file is created, or null if marker_file_path was not set"
}
