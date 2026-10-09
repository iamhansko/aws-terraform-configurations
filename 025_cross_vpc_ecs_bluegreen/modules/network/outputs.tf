output "hub_vpc_id" {
  value       = aws_vpc.hub.id
  description = "ID of the hub VPC"
}
output "hub_vpc_cidr_block" {
  value       = aws_vpc.hub.cidr_block
  description = "CIDR block of the hub VPC, re-exposed from the input so a caller building a security group rule or a route does not restate it (rules.md B-5)"
}
output "app_vpc_id" {
  value       = aws_vpc.app.id
  description = "ID of the app VPC"
}
output "app_vpc_cidr_block" {
  value       = aws_vpc.app.cidr_block
  description = "CIDR block of the app VPC"
}
# The default security group of each VPC, which exists whether or not anything is attached to it.
#
# Every one of the _monolithic template's workload groups opened all traffic from its VPC's
# default group, and nothing in the project is attached to that group - so those rules are inert
# as built. They are reproduced rather than dropped because they are the hatch the template left
# for an instance launched by hand into either VPC, and removing them silently would change what
# the original did. The root passes these IDs in, which is where the decision is visible.
output "hub_default_security_group_id" {
  value       = aws_vpc.hub.default_security_group_id
  description = "Default security group of the hub VPC. Allowed inbound on the hub NLB group, reproducing the _monolithic template - nothing in this project is attached to it, so the rule is a hatch for an instance launched by hand rather than a path anything uses"
}
output "app_default_security_group_id" {
  value       = aws_vpc.app.default_security_group_id
  description = "Default security group of the app VPC. Allowed inbound on the ECS service, ALB, app NLB, container instance and Aurora groups, reproducing the _monolithic template"
}
output "hub_public_subnet_ids" {
  value       = [for subnet in aws_subnet.hub_public : subnet.id]
  description = "All hub public subnets, for the internet-facing NLB"
}
output "hub_public_subnet_ids_by_zone" {
  value       = { for suffix, subnet in aws_subnet.hub_public : suffix => subnet.id }
  description = "Hub public subnets keyed by zone suffix, for a caller that needs one specific zone - the workbench takes a single subnet (rules.md C-3)"
}
output "app_public_subnet_ids" {
  value       = [for subnet in aws_subnet.app_public : subnet.id]
  description = "All app public subnets. These hold the NAT gateways; nothing in this project is launched into them"
}
output "app_private_subnet_ids" {
  value       = [for subnet in aws_subnet.app_private : subnet.id]
  description = "All app private subnets, for the container instances, the tasks, the internal ALB and the internal NLB"
}
output "app_internal_subnet_ids" {
  value       = [for subnet in aws_subnet.app_internal : subnet.id]
  description = "All app internal subnets, for the Aurora subnet group. These have no route to the internet in either direction"
}
output "app_private_subnet_ids_by_zone" {
  value       = { for suffix, subnet in aws_subnet.app_private : suffix => subnet.id }
  description = "App private subnets keyed by zone suffix"
}
output "peering_connection_id" {
  value       = aws_vpc_peering_connection.peering.id
  description = "ID of the VPC peering connection"
}
output "peering_accept_status" {
  value       = aws_vpc_peering_connection.peering.accept_status
  description = "Acceptance state of the peering connection. Worth exposing: with auto_accept unset this reads pending-acceptance and nothing crosses between the VPCs, which is the shape of failure the _monolithic template would have produced"
}
output "hub_flow_log_group_name" {
  value       = aws_cloudwatch_log_group.hub_flow_log.name
  description = "Hub VPC flow log group, re-exposed so the dashboard queries the group this module created rather than a name written twice (rules.md B-5)"
}
output "app_flow_log_group_name" {
  value       = aws_cloudwatch_log_group.app_flow_log.name
  description = "App VPC flow log group"
}
output "route_tables_command" {
  value       = "aws ec2 describe-route-tables --filters Name=vpc-id,Values=${aws_vpc.hub.id},${aws_vpc.app.id} --query 'RouteTables[].[Tags[?Key==`Name`].Value|[0],Routes[].[DestinationCidrBlock,GatewayId,NatGatewayId,VpcPeeringConnectionId]]' --output json"
  description = "Command printing every route table in both VPCs with its routes. This is where the cross-VPC design is visible: each table carries one route to the peering connection, and the internal tier carries nothing else"
}
