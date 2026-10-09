output "transit_gateway_id" {
  value       = aws_ec2_transit_gateway.tgw.id
  description = "ID of the transit gateway. Both VPC route tables name it as a route target, and both attachments name it as their gateway"
}
output "transit_gateway_arn" {
  value       = aws_ec2_transit_gateway.tgw.arn
  description = "ARN of the transit gateway, for a resource share or an IAM condition"
}
output "association_default_route_table_id" {
  value       = aws_ec2_transit_gateway.tgw.association_default_route_table_id
  description = "ID of the route table attachments are associated with by default. This single attribute is what replaced the _monolithic template's Lambda-backed custom resource, which existed only to look this value up with ec2:DescribeTransitGateways because CloudFormation does not return it - see main.tf"
}
output "propagation_default_route_table_id" {
  value       = aws_ec2_transit_gateway.tgw.propagation_default_route_table_id
  description = "ID of the route table attachment CIDRs are propagated into by default. The same table as the association one with this module's defaults, and exposed separately because that is a consequence of both settings being enabled rather than a guarantee - a configuration that disables one of them has two different tables, and a route added to the wrong one is accepted and never used"
}
output "route_table_command" {
  value       = "aws ec2 search-transit-gateway-routes --transit-gateway-route-table-id ${aws_ec2_transit_gateway.tgw.association_default_route_table_id} --filters Name=state,Values=active --query 'Routes[].[DestinationCidrBlock,Type,State]' --output table"
  description = "The gateway's effective routing table, which no Terraform attribute holds: the static default route is in state, the two propagated VPC CIDRs are not. Three active routes - 0.0.0.0/0 static plus both VPC CIDRs propagated - is the healthy result, and a missing spoke CIDR explains traffic that leaves and never comes back"
}
