output "instance_id" {
  value       = aws_instance.app_server_ec2.id
  description = "ID of the instance. This is what the root registers against the target group, and because target_type is instance it is the id rather than an address that the registration takes"
}
output "private_ip" {
  value       = aws_instance.app_server_ec2.private_ip
  description = "Private address of the instance. The load balancer resolves this itself from the instance id, so it is here for reading rather than for wiring"
}
output "public_ip" {
  value       = aws_instance.app_server_ec2.public_ip
  description = "Public address of the instance, which exists so that the userdata can reach dnf and pip in a default VPC with no NAT gateway. Nothing can connect to it inbound unless ingress_cidr_blocks was set"
}
output "security_group_id" {
  value       = aws_security_group.app_server_security_group.id
  description = "ID of this instance's security group, for granting it anything further from the root"
}
output "iam_role_arn" {
  value       = aws_iam_role.app_server_iam_role.arn
  description = "ARN of the instance role, for granting it anything further from the root (rules.md C-1)"
}
output "iam_role_name" {
  value       = aws_iam_role.app_server_iam_role.name
  description = "Name of the instance role, for attaching further policies from the root without this module changing"
}
output "app_port" {
  value       = var.app_port
  description = "Port the app binds, handed straight back out so a caller comparing it against the load balancer's target port reads the value the app was actually configured with (rules.md B-5)"
}
output "app_directory" {
  value       = var.app_directory
  description = "Where main.py, utils/ and the SQLite database are, re-exposed so a command the root publishes does not restate the path (rules.md B-5)"
}
output "service_name" {
  value       = var.service_name
  description = "Name of the systemd unit, re-exposed for the same reason as the directory - the status and log commands the root publishes are built from it (rules.md B-5)"
}
output "index_path" {
  value       = local.index_path
  description = <<-DESC
    The route the app answers a plain GET on, which is what the load balancer's health check has to request.

    Deliberately not wired into the load balancer module. That module's security group is this module's
    ingress source, so a reference in the other direction would close a cycle between the two modules and
    Terraform would refuse to plan. The health check path is a root variable instead, and this output exists
    so the two can be compared - a health check pointed at a path the app does not route reads unhealthy
    forever while the app is working, and the load balancer answers 503.
  DESC
}
output "lookup_path" {
  value       = local.lookup_path
  description = "The route whose query parameter is concatenated into a SQL statement, taken from the app source this module writes. The root builds the demo's probes against it rather than restating \"/lookup\" (rules.md B-5)"
}
output "lookup_query_parameter" {
  value       = local.lookup_query_parameter
  description = "Name of the query parameter the lookup route reads. This is the parameter the injection probe goes into, and the managed SQLi rule group inspects query arguments - so a probe sent under the wrong name reaches the app unmatched and returns 200, which looks exactly like WAF not working"
}
output "login_path" {
  value       = local.login_path
  description = "The other injectable route, which concatenates name and secret into a WHERE clause. Not used by the published probes, but it is the second thing to try when demonstrating that the application itself is the problem the web ACL is covering for"
}
output "session_command" {
  value       = "aws ssm start-session --target ${aws_instance.app_server_ec2.id}"
  description = "The way onto this host. There is no SSH ingress rule and no public route to it, so this is it - and it works only because the instance role carries SSM permissions, which the _monolithic template did not give it"
}
output "service_status_command" {
  value       = "sudo systemctl status ${var.service_name} --no-pager; sudo journalctl -u ${var.service_name} -n 50 --no-pager"
  description = "Run this on the instance. A service restarting in a loop with ModuleNotFoundError naming flask means pip never ran, which points at egress or at the interpreter; naming utils means main.py and utils/ are no longer in the same directory"
}
output "cloud_init_log_command" {
  value       = "sudo tail -n 200 /var/log/cloud-init-output.log"
  description = "Every line of the bootstrap, with set -x. Connection timeouts against dnf and pip in here mean the security group lost its egress rule or the instance has no public address - which in a default VPC with no NAT gateway amount to the same thing"
}
