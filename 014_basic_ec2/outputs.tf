# Plain outputs here, rather than the local.outputs map the projects with a
# code-server instance use. That pattern exists to keep a README rendered onto
# the instance in step with outputs.tf (rules.md H-2); there is no code-server in
# this root module, so there is no second copy of these values to drift from.
output "app_url" {
  value       = "http://${module.public_ec2.public_ip}:${var.app_port}"
  description = "URL of the demo app on the public instance. Reachable only while allow_app_from_anywhere is true"
}
output "public_instance_id" {
  value       = module.public_ec2.instance_id
  description = "ID of the public instance"
}
output "private_instance_id" {
  value       = module.private_ec2.instance_id
  description = "ID of the private instance, which has no public IP"
}
output "private_instance_ip" {
  value       = module.private_ec2.private_ip
  description = "Private IP of the private instance, the address to curl from the public instance"
}
output "private_key_parameter" {
  value       = "/ec2/keypair/${module.key_pair.key_pair_id}"
  description = "Name of the SSM parameter holding the generated SSH private key. The parameter is a SecureString, so only its name is exposed here rather than the key itself"
}
output "public_instance_session_command" {
  value       = "aws ssm start-session --target ${module.public_ec2.instance_id}"
  description = "Command opening a shell on the public instance through SSM Session Manager, with no inbound SSH rule required"
}
output "private_instance_session_command" {
  value       = "aws ssm start-session --target ${module.private_ec2.instance_id}"
  description = "Command opening a shell on the private instance through SSM. It works without a bastion hop because the private subnet reaches the SSM endpoints through the NAT gateway"
}
output "private_reachability_check_command" {
  value       = "curl -sS --max-time 5 http://${module.private_ec2.private_ip}:${var.app_port} || echo blocked"
  description = "Run from the public instance it connects, run from anywhere else it times out: the private instance's security group admits only the public instance's security group"
}
output "app_status_command" {
  value       = "sudo systemctl status demo-app --no-pager"
  description = "Command checking the demo app's systemd unit on the public instance. The app runs as a unit rather than in the foreground of user data, so it survives a reboot"
}
