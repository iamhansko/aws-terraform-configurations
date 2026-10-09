output "instance_id" {
  value       = aws_instance.queue_worker_ec2.id
  description = "ID of the worker instance, for start-session and describe-instances"
}
output "private_ip" {
  value       = aws_instance.queue_worker_ec2.private_ip
  description = "Private address of the worker. This is the address to SSH to from the workbench, which is the only host whose security group this one admits"
}
output "public_ip" {
  value       = aws_instance.queue_worker_ec2.public_ip
  description = "Public address of the worker. It has one because the subnet assigns one and it needs outbound access, but no inbound rule here admits the internet - the SSH rules name the workbench's security group"
}
output "security_group_id" {
  value       = aws_security_group.queue_worker_security_group.id
  description = "ID of the worker's security group"
}
output "iam_role_arn" {
  value       = aws_iam_role.queue_worker_iam_role.arn
  description = "ARN of the worker's instance role, which is the role the narrowed policy set is attached to - and, in the conversion before it was corrected, the role that was created and then attached to nothing (rules.md A-3)"
}
output "worker_script_path" {
  value       = var.worker_script_path
  description = "Where the worker was written, handed back out so the root's commands and any later association name one value (rules.md B-5)"
}
output "queue_url" {
  value       = var.queue_url
  description = "The queue this host was configured to drain, handed straight back out (rules.md B-5). A worker that logs nothing while messages pile up is this value pointing at a different queue than the one being watched"
}
output "log_group_name" {
  value       = var.log_group_name
  description = "Log group the agent on this host ships to, re-exposed so a mismatch with the group the metric filter watches is visible in outputs rather than only as an empty metric (rules.md B-5)"
}
output "worker_service_name" {
  value       = var.worker_service_name
  description = "Name of the systemd unit, so the start and status commands do not restate it"
}
output "start_worker_command" {
  value       = "sudo systemctl start ${var.worker_service_name}"
  description = "Starts the drain. Run it over SSH from the workbench or through SSM Session Manager; with start_worker true it is already running and this is a no-op"
}
output "worker_status_command" {
  value       = "sudo systemctl status ${var.worker_service_name} --no-pager && sudo journalctl -u ${var.worker_service_name} -n 50 --no-pager"
  description = "Whether the worker is running and what it last said. An AccessDenied loop here with ReceiveMessage named is the inline queue policy not being in place - which the instance's depends_on exists to prevent"
}
output "worker_log_command" {
  value       = "sudo tail -n 50 ${var.log_file_path}"
  description = "The worker's own log file on the instance, before CloudWatch is involved. Lines here but no metric datapoints narrows the fault to the agent or the filter pattern; no lines at all with the service running means the logging call is being discarded, which is what a missing level=logging.INFO does"
}
output "queue_depth_command" {
  value       = "aws sqs get-queue-attributes --queue-url ${var.queue_url} --attribute-names ApproximateNumberOfMessages ApproximateNumberOfMessagesNotVisible --output table"
  description = "The backlog, as seen from this host using its own role - which also checks that the inline policy's sqs:GetQueueAttributes is in place"
}
output "cloud_init_log_command" {
  value       = "sudo tail -n 200 /var/log/cloud-init-output.log"
  description = "Every line of the bootstrap, with set -x. Connection timeouts on dnf here mean the security group has no egress rule; a heredoc that appears to have swallowed the rest of the script means the .tf file was saved with CRLF line endings (rules.md A-4)"
}
