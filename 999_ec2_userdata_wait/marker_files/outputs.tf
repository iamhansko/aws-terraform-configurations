output "vscode" {
  value       = "http://${module.vscode_ec2.public_ip}:8000"
  description = "Public IP Address of the VS Code Server EC2 instance"
}
