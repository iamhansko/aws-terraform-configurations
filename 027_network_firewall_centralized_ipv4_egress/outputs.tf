# Every value here is a projection of local.outputs in main.tf. No output in this file carries a value
# expression of its own.
#
# That is what rules.md H-2 requires of a root that declares module "vscode_ec2": the work happens inside
# code-server in a browser, where terraform output does not exist, so the same values are written into a
# README on the instance - and the only way to stop the two copies drifting is for both to read one map. An
# output declared here with its own expression would be missing from that README, and nothing would report
# it, because the apply would succeed either way.
#
# The count is the check: this file has twenty-six output blocks and local.outputs has twenty-six entries.
#
# The descriptions are the one thing that is restated, because Terraform does not allow an expression in an
# output description - "Error: Variables not allowed" - so they are literals on both sides while the values
# exist only in the map.
#
# The _monolithic template declared no outputs at all. Twenty-nine resources, three variables, nothing to
# read afterwards - which for a project whose entire subject is whether traffic takes a particular path
# meant there was no way to tell whether it worked.
output "vscode_port_forward_command" {
  value       = local.outputs.vscode_port_forward_command.value
  description = "1. Opens the only route to the workbench IDE: a Session Manager port forward. The instance has no public address, by design"
}
output "vscode_url" {
  value       = local.outputs.vscode_url.value
  description = "The IDE on localhost once the forward is running. No password - code-server runs with auth none behind a loopback listener"
}
output "session_command" {
  value       = local.outputs.session_command.value
  description = "A shell on the workbench without the IDE"
}
output "firewall_status_command" {
  value       = local.outputs.firewall_status_command.value
  description = "2. Whether the firewall is READY and in sync. Apply returns before the endpoints are serving, so a drop test run too early passes for the wrong reason"
}
output "firewall_endpoints_command" {
  value       = local.outputs.firewall_endpoints_command.value
  description = "3. One line per zone: endpoint id, subnet and status. Two READY lines is healthy"
}
output "firewall_endpoint_ids" {
  value       = local.outputs.firewall_endpoint_ids.value
  description = "The endpoint id in each firewall subnet - what the attachment route tables must point at"
}
output "inspection_route_check_command" {
  value       = local.outputs.inspection_route_check_command.value
  description = "4. Each attachment route table's name next to the target of its default route. Both must be vpce- ids, matching the zone in the table's name"
}
output "egress_address_command" {
  value       = local.outputs.egress_address_command.value
  description = "5. Run on the workbench: the address the internet saw. One line that tests the whole inspected path"
}
output "nat_gateway_public_ips" {
  value       = local.outputs.nat_gateway_public_ips.value
  description = "The two NAT gateway addresses by zone. The command above must return the one for the workbench's zone"
}
output "workbench_availability_zone" {
  value       = local.outputs.workbench_availability_zone.value
  description = "The workbench's zone, which says which NAT gateway address is the expected answer"
}
output "blocked_dns_command" {
  value       = local.outputs.blocked_dns_command.value
  description = "6. A DNS query to a public resolver, which the stateful rules should drop"
}
output "allowed_dns_command" {
  value       = local.outputs.allowed_dns_command.value
  description = "The control: the same name through the Amazon resolver, which never reaches the firewall and should answer"
}
output "blocked_ping_command" {
  value       = local.outputs.blocked_ping_command.value
  description = "7. ICMP, which the stateless rule drops silently. 100% packet loss is the pass condition"
}
output "firewall_alert_log_command" {
  value       = local.outputs.firewall_alert_log_command.value
  description = "8. What the firewall dropped - the direct evidence that the rules fired rather than something upstream failing"
}
output "firewall_flow_log_command" {
  value       = local.outputs.firewall_flow_log_command.value
  description = "9. What the firewall passed - the evidence that successful traffic went through it rather than around it"
}
output "transit_gateway_route_table_command" {
  value       = local.outputs.transit_gateway_route_table_command.value
  description = "10. The hub's effective routes. Three active ones is healthy: the static default plus both VPC CIDRs propagated"
}
output "transit_gateway_id" {
  value       = local.outputs.transit_gateway_id.value
  description = "ID of the transit gateway both VPC route tables target"
}
output "transit_gateway_association_default_route_table_id" {
  value       = local.outputs.transit_gateway_association_default_route_table_id.value
  description = "The route table id the original discovered with a Lambda function, and which is a plain attribute of the gateway in Terraform"
}
output "firewall_name" {
  value       = local.outputs.firewall_name.value
  description = "Name of the firewall, which is the handle every describe-firewall call takes"
}
output "firewall_log_group_names" {
  value       = local.outputs.firewall_log_group_names.value
  description = "CloudWatch log group per enabled firewall log type. Empty means logging is off"
}
output "egress_vpc_id" {
  value       = local.outputs.egress_vpc_id.value
  description = "ID of the egress VPC that holds the firewall and the NAT gateways"
}
output "app_vpc_id" {
  value       = local.outputs.app_vpc_id.value
  description = "ID of the spoke VPC, which has no internet gateway and therefore no path out except the inspected one"
}
output "workbench_instance_id" {
  value       = local.outputs.workbench_instance_id.value
  description = "ID of the workbench instance, which the port forward and the session command target"
}
output "workbench_private_ip" {
  value       = local.outputs.workbench_private_ip.value
  description = "Private address of the workbench. Its only address"
}
output "private_key_command" {
  value       = local.outputs.private_key_command.value
  description = "Retrieves the generated SSH private key from Parameter Store. A command rather than the key, so this does not print a secret"
}
output "cloud_init_log_command" {
  value       = local.outputs.cloud_init_log_command.value
  description = "The workbench's bootstrap log. First place to look when the IDE does not answer"
}
