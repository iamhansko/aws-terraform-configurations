output "public_ip" {
  value       = aws_instance.vscode_ec2.public_ip
  description = "Public IP address of the VS Code EC2 instance"
}

output "instance_id" {
  value       = aws_instance.vscode_ec2.id
  description = "ID of the VS Code EC2 instance"
}

output "marker_file_path" {
  value       = var.marker_file_path
  description = "Directory where the userdata completion marker file is created, or null if marker_file_path was not set"
}
