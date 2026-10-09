output "vpc_id" {
  value       = aws_vpc.app_vpc.id
  description = "ID of the app VPC"
}
output "vpc_cidr_block" {
  value       = aws_vpc.app_vpc.cidr_block
  description = "Primary CIDR block of the app VPC, re-exposed so the egress VPC's return route reads the created block rather than restating the variable (rules.md B-5)"
}
output "private_subnet_ids" {
  value       = [for subnet in aws_subnet.private : subnet.id]
  description = "Private subnets, which hold both the transit gateway attachment and the workbench"
}
output "private_subnet_ids_by_zone" {
  value       = { for suffix, subnet in aws_subnet.private : suffix => subnet.id }
  description = "Private subnets keyed by zone suffix, for a caller that needs one specific zone - the workbench takes the first, as the _monolithic template launched its instance into app-private-sn-a"
}
output "route_table_id" {
  value       = aws_route_table.private.id
  description = "ID of this VPC's only route table, re-exposed because the root writes the default route into it: that route points at the transit gateway, so it belongs to neither this module nor the gateway's (rules.md C-1)"
}
output "route_tables_command" {
  value       = "aws ec2 describe-route-tables --filters Name=vpc-id,Values=${aws_vpc.app_vpc.id} --query 'RouteTables[].{Name:Tags[?Key==`Name`].Value|[0],Routes:Routes[].[DestinationCidrBlock,TransitGatewayId,GatewayId,NatGatewayId]}' --output json"
  description = "Every route table in the app VPC. There should be exactly one 0.0.0.0/0 entry and it should name a tgw- id. A GatewayId or NatGatewayId appearing here would mean this VPC acquired its own way out and the demo is no longer measuring centralized egress"
}
