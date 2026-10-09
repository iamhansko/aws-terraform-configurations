# Every value here is a projection of local.outputs in main.tf and nothing else (rules.md H-2). No
# output in this file builds its own expression: the same map is rendered into
# /home/ec2-user/README.md on the workbench by aws_ssm_association.vscode_readme, and an output with
# a value of its own would be absent from that README with nothing to report the omission - the apply
# would succeed either way.
#
# The count of output blocks here must equal the number of entries in local.outputs. Seventeen as of
# this file. The keys are known before plan even though the values are not, so the two can be
# compared mechanically:
#
#   echo '[for k, v in local.outputs : k]' | terraform console
#
# The description strings are the one thing duplicated between this file and the map, and that is a
# language limit rather than a choice: Terraform does not allow an expression in an output's
# description and rejects a reference there with "Variables not allowed". The values are still
# defined exactly once.
#
# rules.md H-1 does not apply to this root. It governs a root that declares both an EKS cluster and a
# vscode_ec2, and there is no cluster anywhere in this project - so kubectl, eksctl, helm and docker
# are not installed on the workbench, and installing them would be adding four tools with nothing to
# point at. What the workbench carries instead is bind-utils, because dig against an external
# resolver is one of the two probes that would show the firewall dropping traffic.
output "port_forward_command" {
  value       = local.outputs.port_forward_command.value
  description = "Forwards code-server to localhost. The only route to it: the instance is in a private subnet of a VPC with no internet gateway, so there is no URL to publish and no security group rule that could create one. code-server runs with auth: none, which is safe here only because the forwarded port is the credential"
}
output "session_command" {
  value       = local.outputs.session_command.value
  description = "Session Manager onto the workbench. Works for the same reason the port forward does - the SSM agent dials out through the egress path, so nothing has to dial in"
}
output "egress_check_command" {
  value       = local.outputs.egress_check_command.value
  description = "Path of the probe script on the workbench. It prints this host's own address, the address the internet sees it as, a resolver query inside the VPC, the same query against an external resolver, and a ping. The first two answer whether egress is centralized; the last two answer whether the firewall is inspecting it"
}
output "expected_source_addresses" {
  value       = local.outputs.expected_source_addresses.value
  description = "The egress VPC's NAT gateway addresses - the correct answer to the script's second probe. The workbench's own 172.16 address coming back would mean it found some other way out, and a timeout means one of the six routes is wrong"
}
output "firewall_inspects_egress_traffic" {
  value       = local.outputs.firewall_inspects_egress_traffic.value
  description = "Whether the Network Firewall is in the data path. It is not, and that is reproduced from the _monolithic template rather than introduced here: no route table in either VPC names a firewall endpoint, and the firewall subnets have no route table association at all. Both rule groups are therefore unreachable. The three route changes that would close it are documented above aws_networkfirewall_firewall in modules/network_firewall/main.tf"
}
output "firewall_flow_log_command" {
  value       = local.outputs.firewall_flow_log_command.value
  description = "Tails the firewall's FLOW log after the probes have run. Empty output is the positive confirmation of firewall_inspects_egress_traffic - the firewall is up and receiving nothing. Logging is an addition to the _monolithic template, which configured none; without it an idle firewall and a bypassed one look identical"
}
output "firewall_describe_command" {
  value       = local.outputs.firewall_describe_command.value
  description = "The firewall's own view of itself: READY, with one endpoint per zone. Worth seeing precisely because it says nothing about whether traffic reaches it - this is the output that makes a bypassed firewall look healthy"
}
output "transit_gateway_routes_command" {
  value       = local.outputs.transit_gateway_routes_command.value
  description = "The gateway's routes. Two rows expected: the static default route to the egress VPC's attachment, and a propagated route back to the app VPC that AWS installs and no plan shows. A row in blackhole state is this project's worst failure mode - it exists, so nothing errors, and matching packets are dropped"
}
output "transit_gateway_attachments_command" {
  value       = local.outputs.transit_gateway_attachments_command.value
  description = "Each attachment and the subnets it was placed in. Check the subnet IDs rather than just the state: an attachment in the egress VPC's public tier reports available and silently sends private addresses at an internet gateway"
}
output "egress_route_tables_command" {
  value       = local.outputs.egress_route_tables_command.value
  description = "The egress VPC's route tables - three of them, not four. The firewall subnets are absent because they have no table, which is firewall_inspects_egress_traffic seen from the routing side"
}
output "app_route_tables_command" {
  value       = local.outputs.app_route_tables_command.value
  description = "The app VPC's single route table. One non-local route, pointing at a tgw- id. A GatewayId or NatGatewayId here would mean this VPC acquired its own way out and the probes no longer measure centralized egress"
}
output "nat_gateway_check_command" {
  value       = local.outputs.nat_gateway_check_command.value
  description = "State of both NAT gateways. A gateway in failed state was created before the internet gateway was attached, and that state is terminal - it does not recover when the attachment lands (rules.md D-1)"
}
output "address_plan" {
  value       = local.outputs.address_plan.value
  description = "Which CIDR block is where. The app VPC's block is also the destination of the return route in the egress VPC's public route table, so the two must agree - they read one variable rather than restating it (rules.md B-5)"
}
output "transit_gateway_route_table_id" {
  value       = local.outputs.transit_gateway_route_table_id.value
  description = "The route table id the _monolithic template deployed a Lambda function, an IAM role, an inline ec2:* policy and a custom resource protocol to discover. It is an attribute of the gateway, and the function it replaces could not have returned it anyway - four reasons are listed above that output in modules/transit_gateway/outputs.tf"
}
output "bootstrap_log_command" {
  value       = local.outputs.bootstrap_log_command.value
  description = "The workbench's boot log, which is where an apply that timed out on the README association is actually explained. A script that stops at wget means the egress path is broken; a log that never starts means the user data failed to parse, which usually means a CR reached a heredoc terminator (rules.md A-4)"
}
output "private_key_command" {
  value       = local.outputs.private_key_command.value
  description = "Fetches the generated private key from SSM, reproducing what CloudFormation's AWS::EC2::KeyPair does. Nothing in this project can use it - no inbound rule, no public address, no route from outside the app VPC"
}
output "workbench_instance_id" {
  value       = local.outputs.workbench_instance_id.value
  description = "The one instance in this project and the source of every probe, with its private address - which is the address that must not come back from the public-address probe"
}
