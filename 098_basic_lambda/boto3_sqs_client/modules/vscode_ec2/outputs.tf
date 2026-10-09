output "instance_id" {
  value       = aws_instance.vscode_ec2.id
  description = "ID of the instance, which is what the root's SSM associations target"
}
output "public_ip" {
  value       = var.associate_elastic_ip ? aws_eip.vscode_ec2[0].public_ip : aws_instance.vscode_ec2.public_ip
  description = "Address the browser connects to. The Elastic IP when one was allocated, so it survives a stop/start - the instance's own public_ip attribute does not"
}
output "private_ip" {
  value       = aws_instance.vscode_ec2.private_ip
  description = "Private address of the instance, for reaching the worker from here"
}
output "vscode_url" {
  value       = "http://${var.associate_elastic_ip ? aws_eip.vscode_ec2[0].public_ip : aws_instance.vscode_ec2.public_ip}:${var.code_server_port}"
  description = "The IDE. http rather than https because code-server is configured with cert: false, and no password because it is configured with auth: none - the address is the only thing protecting it"
}
output "security_group_id" {
  value       = aws_security_group.vscode_ec2_security_group.id
  description = "ID of this instance's security group. The worker module takes this as the source of its SSH rule, and because it is another module's output it has to arrive there as a map value with a static key rather than in a list (rules.md B-8)"
}
output "iam_role_arn" {
  value       = aws_iam_role.vscode_ec2_iam_role.arn
  description = "ARN of the instance role, for granting it anything further from the root (rules.md C-1)"
}
output "iam_role_name" {
  value       = aws_iam_role.vscode_ec2_iam_role.name
  description = "Name of the instance role, for attaching further policies from the root without this module changing"
}
output "marker_file_path" {
  value       = var.marker_file_path
  description = "Directory the user data writes its completion marker into, or null if no marker was requested. Handed straight back out so the root's associations wait on a path defined in exactly one place (rules.md B-5)"
}
output "load_generator_path" {
  value       = var.load_generator_path
  description = "Where the generator was written. Re-exposed for the same reason as the marker path: the root's association rewrites this file and the run command names it, and neither should restate the path (rules.md B-5)"
}
output "run_load_generator_command" {
  value       = "${var.python_command} ${var.load_generator_path}"
  description = "Run this in the code-server terminal. It resolves the function URL by name, then posts in batches - the counts it prints are successes per batch, and a batch short of its size means Lambda answered 429 more times than the retry budget could absorb"
}
output "cloud_init_log_command" {
  value       = "sudo tail -n 200 /var/log/cloud-init-output.log"
  description = "Every line of the bootstrap, with set -x. First place to look when the IDE does not answer: a connection timeout with dnf and wget in this log means the security group has no egress rule, which is the defect described in main.tf"
}
