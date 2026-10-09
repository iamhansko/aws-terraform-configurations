output "instance_id" {
  value       = aws_instance.vscode_ec2.id
  description = "ID of the instance, which is what the root's SSM association targets and what every Session Manager command below names"
}
output "private_ip" {
  value       = aws_instance.vscode_ec2.private_ip
  description = "Private address of the instance. There is no public one: this VPC has no internet gateway, which is the property that forces every packet this instance sends through the firewall"
}
output "availability_zone" {
  value       = aws_instance.vscode_ec2.availability_zone
  description = "Zone the instance landed in, taken from the instance rather than from the subnet variable. This is the zone whose firewall endpoint and NAT gateway its traffic should use, so it is the value to compare the observed egress address against"
}
output "security_group_id" {
  value       = aws_security_group.vscode_ec2_security_group.id
  description = "ID of this instance's security group. A group this module created, rather than the VPC default group the _monolithic template attached - and because it is another module's output from a caller's point of view, it has to arrive anywhere it is iterated as a map value with a static key (rules.md B-8)"
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
  description = "Directory the user data writes its completion marker into, or null if no marker was requested. Handed straight back out so the root's association waits on a path defined in exactly one place (rules.md B-5)"
}
output "code_server_port" {
  value       = var.code_server_port
  description = "Port code-server listens on, re-exposed so the port forward command and the URL in the root's outputs read one value rather than restating 8000 (rules.md B-5)"
}
output "port_forward_command" {
  value       = "aws ssm start-session --target ${aws_instance.vscode_ec2.id} --document-name AWS-StartPortForwardingSession --parameters '{\"portNumber\":[\"${var.code_server_port}\"],\"localPortNumber\":[\"${var.code_server_port}\"]}'"
  description = <<-DESC
    Opens the IDE. Leave this running and open the URL below in a browser.

    This is the only way in, and that is a property of the architecture rather than a limitation: the
    instance is in a VPC with no internet gateway, so there is no address to connect to. The agent on the
    instance makes the connection to its own loopback address, so this traffic does not cross the security
    group and needs no inbound rule.

    It needs the Session Manager plugin installed locally. "SessionManagerPlugin is not found" is that,
    not a permissions problem. "TargetNotConnected" means the agent has not registered - check the
    instance role has SSM access and that cloud-init could reach the SSM endpoints through the firewall.
  DESC
}
output "vscode_url" {
  value       = "http://localhost:${var.code_server_port}"
  description = "The IDE, once the port forward is running. localhost rather than an instance address because the forward terminates locally. http and no password: code-server is configured with cert false and auth none, which is safe only because the listener is on loopback and the session that reaches it was authorized by IAM"
}
output "session_command" {
  value       = "aws ssm start-session --target ${aws_instance.vscode_ec2.id}"
  description = "A shell on the instance without the IDE. Faster than the port forward when all that is wanted is to run one of the checks below"
}
output "egress_address_command" {
  value       = "curl -s ${var.address_reflector_url}"
  description = <<-DESC
    The end-to-end test. Run it on the instance; it prints the address the internet saw.

    The answer must be one of the two NAT gateway Elastic IPs, and specifically the one in this instance's
    own zone - that single line confirms the whole chain: spoke route table, transit gateway, attachment
    route table, firewall endpoint, firewall subnet route table, NAT gateway, public route table, internet
    gateway. The other zone's address means the transit gateway crossed a zone boundary. An address that
    is neither means traffic is leaving by a path this project does not control, which is what putting the
    instance in a public subnet would do. No answer at all means the chain is broken somewhere, and the
    firewall's flow log says whether the packet got as far as the firewall.
  DESC
}
output "allowed_dns_command" {
  value       = "dig +short ${var.dns_check_hostname}"
  description = "Resolution through the Amazon resolver, which should answer. The query matches the VPC's local route, so it never reaches the transit gateway or the firewall - this is the control for the next command, and the reason the instance can install anything at all while DNS egress is blocked"
}
output "blocked_dns_command" {
  value       = "dig +time=5 +tries=1 @${var.blocked_resolver_address} ${var.dns_check_hostname}"
  description = "The same query sent to a public resolver, which should time out. It leaves the VPC, so the firewall's stateful rules see it and drop it on port 53 in both protocols. The pair of commands either side of this one is what distinguishes a firewall drop from broken DNS, and the drop should appear in the firewall's alert log"
}
output "blocked_ping_command" {
  value       = "ping -c 3 -W 3 ${var.blocked_ping_address}"
  description = "ICMP, which the stateless rule drops. 100% packet loss is the pass condition - the action is aws:drop, which discards silently, so there is no \"unreachable\" reply to distinguish it from a routing black hole. The alert log is what distinguishes them"
}
output "cloud_init_log_command" {
  value       = "sudo tail -n 200 /var/log/cloud-init-output.log"
  description = "Every line of the bootstrap, with set -x. First place to look when the IDE does not answer: connection timeouts on dnf and wget here mean the instance never had outbound access, which in this project points at the security group's egress rule or at an incomplete egress chain rather than at the firewall's rules"
}
