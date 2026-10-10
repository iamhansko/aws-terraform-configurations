output "instance_id" {
  value       = aws_instance.bastion_ec2.id
  description = "ID of the bastion instance, which the completion check in the root targets with an SSM association"
}
output "public_ip" {
  value       = aws_eip.bastion_elastic_ip.public_ip
  description = "Elastic IP associated with the instance"
}
output "security_group_id" {
  value       = aws_security_group.bastion_security_group.id
  description = "ID of the bastion security group. The container instance group admits SSH from this group, which is what makes the instance a hop to the private subnets"
}
output "iam_role_name" {
  value       = aws_iam_role.bastion_iam_role.name
  description = "Generated name of the instance role"
}
output "iam_role_arn" {
  value       = aws_iam_role.bastion_iam_role.arn
  description = "ARN of the instance role"
}
output "marker_file_path" {
  value       = var.marker_file_path
  description = "Directory the completion marker is written to, re-exposed so the caller's wait loop and this module's userdata read one value rather than each holding their own copy (rules.md B-5)"
}
output "marker_file" {
  value       = var.marker_file_path == null ? null : "${var.marker_file_path}/bastion_build"
  description = "Full path of the completion marker, including the filename this module chose. Null when no marker is configured"
}
output "build_log_command" {
  value       = "aws ssm start-session --target ${aws_instance.bastion_ec2.id} --document-name AWS-StartInteractiveCommand --parameters command='sudo tail -n 200 /var/log/cloud-init-output.log'"
  description = "The end of the builder's log, over Session Manager so it works with the SSH port closed. This is the only place a failed dnf, docker login, build, push or upload is recorded - the instance still reports running either way"
}
output "ssh_command" {
  value       = "ssh -i <private-key-file> ec2-user@${aws_eip.bastion_elastic_ip.public_ip}"
  description = "SSH command for the bastion. The private key comes from Parameter Store - see the key pair module's retrieval command - and this only works while ssh_ingress_cidr_blocks admits the caller"
}
output "reupload_command" {
  value       = "aws s3 cp ${var.source_object_key} s3://${var.source_bucket_name}/${var.source_object_key}"
  description = "Run from the build directory on the bastion, this is the command that starts a pipeline run. The upload the userdata performs happens during apply and may land before the CloudTrail trail is recording, so this is also the reliable way to trigger the first deployment"
}
output "build_directory" {
  value       = local.build_directory
  description = "Directory on the instance holding main.go, the seed Dockerfile and the archive, so that re-running the upload by hand does not require guessing where the files are"
}
