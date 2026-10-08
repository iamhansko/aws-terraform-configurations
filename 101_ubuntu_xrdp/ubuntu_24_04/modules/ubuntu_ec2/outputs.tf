output "instance_id" {
  value       = aws_instance.ubuntu_ec2.id
  description = "ID of the instance"
}
output "public_ip" {
  value       = aws_instance.ubuntu_ec2.public_ip
  description = "Public address of the instance, which is what an RDP client connects to"
}
output "private_ip" {
  value       = aws_instance.ubuntu_ec2.private_ip
  description = "Private address of the instance"
}
output "security_group_id" {
  value       = aws_security_group.ubuntu_ec2_security_group.id
  description = "ID of the security group, so a caller can reference it as a source in another group"
}
output "iam_role_arn" {
  value       = aws_iam_role.ubuntu_ec2_iam_role.arn
  description = "ARN of the instance role, for a caller that needs to grant this instance access to something it owns"
}
output "iam_role_name" {
  value       = aws_iam_role.ubuntu_ec2_iam_role.name
  description = "Name of the instance role"
}
# The three values below are inputs handed back out, so the caller does not keep
# a second copy of them to build its own outputs from (rules.md B-5). The RDP
# endpoint in particular is the port this module opened and the address it was
# given - assembling it in the root would mean the root restating the port.
output "rdp_endpoint" {
  value       = "${aws_instance.ubuntu_ec2.public_ip}:${var.rdp_port}"
  description = "Address and port for the RDP client"
}
output "rdp_port" {
  value       = var.rdp_port
  description = "Port xrdp listens on and the security group opens"
}
output "username" {
  value       = "ubuntu"
  description = "Account the RDP login uses. Fixed rather than a variable: it is the default user of the Ubuntu cloud image, and the userdata sets the password on that account and adds it to sudo and docker"
}
output "password" {
  value       = var.password
  description = "Password set on the ubuntu account. Deliberately not sensitive, so it appears in terraform output where a reader can use it - see the variable for what that costs"
}
output "xrdp_status_command" {
  value       = "aws ssm start-session --target ${aws_instance.ubuntu_ec2.id} --document-name AWS-StartInteractiveCommand --parameters command='systemctl is-active xrdp && ss -lntp | grep ${var.rdp_port}'"
  description = "Whether xrdp is listening yet. The desktop install and the reboot that follows it take several minutes after apply returns, and during that window the port first answers, then stops answering, then answers for good - so a refused or timed-out connection shortly after apply is this rather than a broken configuration"
}
