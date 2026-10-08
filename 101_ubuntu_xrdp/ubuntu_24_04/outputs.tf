# These outputs carry their value expressions directly rather than projecting a
# local.outputs map.
#
# That map exists to keep a root's outputs and the README written onto a VS Code
# instance from drifting apart, so it applies only to roots that declare
# module "vscode_ec2" (rules.md H-2). The instance here runs a GNOME desktop
# reached over RDP, not code-server, and no SSM association writes a README onto
# it - the person who connects gets a desktop, not a file to read - so there is
# no second copy of these values to keep in step.
output "rdp_endpoint" {
  value       = module.ubuntu_ec2.rdp_endpoint
  description = "Address and port to put into the RDP client. Nothing answers here for several minutes after apply returns: cloud-init has to install the desktop, and the reboot that follows it is what makes the port stay open - use xrdp_status_command to tell waiting from broken"
}
output "username" {
  value       = module.ubuntu_ec2.username
  description = "Account to log in as"
}
output "password" {
  value       = module.ubuntu_ec2.password
  description = "Password for that account. Printed rather than marked sensitive because it is needed to connect, which also means it is in the state file and readable from the instance metadata service"
}
output "instance_id" {
  value       = module.ubuntu_ec2.instance_id
  description = "ID of the instance, for describe-instances and start-session"
}
output "xrdp_status_command" {
  value       = module.ubuntu_ec2.xrdp_status_command
  description = "Whether xrdp is listening yet. Expect three phases after apply: the port answers once xrdp is installed, stops answering while ubuntu-desktop hands the interface to NetworkManager, then answers for good after the automatic reboot"
}
output "private_key_command" {
  value       = module.key_pair.private_key_command
  description = "Retrieves the generated SSH private key from Parameter Store. RDP is the way in; this is for the case where the desktop or xrdp did not come up and the instance has to be inspected over SSH"
}
output "vpc_id" {
  value       = module.network.vpc_id
  description = "ID of the VPC"
}
output "public_subnet_id" {
  value       = module.network.public_subnet_a_id
  description = "ID of the public subnet holding the instance"
}
