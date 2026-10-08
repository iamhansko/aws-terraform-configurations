output "instance_id" {
  value       = aws_instance.image_builder_ec2.id
  description = "ID of the instance, which the caller's SSM association targets and which start-session names"
}
output "public_ip" {
  value       = aws_instance.image_builder_ec2.public_ip
  description = "Public address of the instance"
}
output "private_ip" {
  value       = aws_instance.image_builder_ec2.private_ip
  description = "Private address of the instance"
}
output "security_group_id" {
  value       = aws_security_group.image_builder_security_group.id
  description = "ID of the security group, so a caller can reference it as a source in another group"
}
output "iam_role_arn" {
  value       = aws_iam_role.image_builder_iam_role.arn
  description = "ARN of the instance role"
}
output "iam_role_name" {
  value       = aws_iam_role.image_builder_iam_role.name
  description = "Name of the instance role"
}
# Inputs handed back out so the caller builds its association and its outputs from one value rather than
# keeping a second copy (rules.md B-5). The marker path matters most: the caller's association polls for
# a file under it, and a root that restated the path would have the two drift apart into an association
# that waits for a file nothing ever writes.
output "marker_file_path" {
  value       = var.marker_file_path
  description = "Directory the completion marker is written in, or null if marker_file_path was not set"
}
output "marker_file" {
  value       = var.marker_file_path == null ? null : "${var.marker_file_path}/image_builder"
  description = "Full path of the completion marker, including the file name the userdata chose. Null when no marker is created. Assembled here so the caller's until loop does not have to know the file name (rules.md B-5)"
}
output "build_directory" {
  value       = local.build_directory
  description = "Directory on the instance holding the Dockerfile and the build context, for a person looking at a failed build by hand"
}
output "image_uri" {
  value       = var.ecr_image_uri
  description = "The reference the build is tagged with and pushed to, handed back out so the caller's verification step asks about exactly what was pushed (rules.md B-5)"
}
output "build_log_command" {
  value       = "aws ssm start-session --target ${aws_instance.image_builder_ec2.id} --document-name AWS-StartInteractiveCommand --parameters command='tail -n 200 /var/log/cloud-init-output.log'"
  description = "The end of the build log. This is where an empty repository is explained, and it is the only place: the script does not stop on error, so a failed dnf, login, build or push leaves no trace in any AWS API - the instance still reports running and the marker file is still written"
}
output "build_status_command" {
  value       = "aws ssm start-session --target ${aws_instance.image_builder_ec2.id} --document-name AWS-StartInteractiveCommand --parameters command='cloud-init status --long; docker images ${var.ecr_image_uri}'"
  description = "Whether cloud-init has finished and whether the image exists locally on the builder. An image present here but absent from ECR narrows the failure to the push, which is almost always the login or the repository policy rather than the build"
}
