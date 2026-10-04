output "instance_id" {
  value       = aws_instance.instance.id
  description = "EC2 instance ID, for an SSM Association targeting this machine"
}

output "private_ip" {
  value       = aws_instance.instance.private_ip
  description = "Private address of the instance"
}

output "private_dns" {
  value       = aws_instance.instance.private_dns
  description = "Private DNS name of the instance. kubeadm is given --node-name=$(hostname -f), which on Amazon Linux resolves to this, so it is also the Kubernetes node name - which is what a nodeSelector has to match"
}

output "public_ip" {
  value       = aws_instance.instance.public_ip
  description = "Public address of the instance, or empty when associate_public_ip_address is false"
}

output "iam_role_arn" {
  value       = aws_iam_role.instance.arn
  description = "ARN of the instance's IAM role"
}

output "iam_role_name" {
  value       = aws_iam_role.instance.name
  description = "Name of the instance's IAM role, for a caller that has to attach another policy to it"
}

output "marker_file_path" {
  value       = var.marker_file_path
  description = "Directory where this instance touches its completion marker, or null when no marker was asked for. Re-exposed so whatever waits on the marker does not restate the path (rules.md B-5)"
}

output "kubernetes_minor_version" {
  value       = var.kubernetes_minor_version
  description = "Kubernetes minor version this machine installed, re-exposed so the workbench's kubectl version can be checked against it (rules.md B-5)"
}
