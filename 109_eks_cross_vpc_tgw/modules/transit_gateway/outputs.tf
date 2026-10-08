output "transit_gateway_id" {
  value       = aws_ec2_transit_gateway.transit_gateway.id
  description = "ID of the transit gateway, which each VPC's peer routes point at"
}

output "transit_gateway_arn" {
  value       = aws_ec2_transit_gateway.transit_gateway.arn
  description = "ARN of the transit gateway"
}

output "route_table_id" {
  value       = aws_ec2_transit_gateway_route_table.transit_gateway_route_table.id
  description = "ID of the gateway's route table. Every attachment is associated with this one table, and propagation is off - so the routes in it are exactly the ones this module wrote"
}

output "attachment_ids" {
  value       = { for label, attachment in aws_ec2_transit_gateway_vpc_attachment.attachment : label => attachment.id }
  description = "Attachment IDs by label. A VPC's route to the gateway has to be created after its attachment, and this is what a caller orders against (rules.md D-2)"
}

output "attachments" {
  value       = aws_ec2_transit_gateway_vpc_attachment.attachment
  description = "The attachment resources themselves, for a caller that needs to depend on one rather than reference its ID"
}

output "routes_check_command" {
  value       = "aws ec2 search-transit-gateway-routes --transit-gateway-route-table-id ${aws_ec2_transit_gateway_route_table.transit_gateway_route_table.id} --filters Name=state,Values=active,blackhole --query 'Routes[].[DestinationCidrBlock,State,TransitGatewayAttachments[0].ResourceId]' --output table"
  description = "Command that lists the gateway's routes and their state. A route in blackhole state is the failure mode here: it exists, so nothing errors, and traffic to it is silently dropped"
}

output "attachments_check_command" {
  value       = "aws ec2 describe-transit-gateway-vpc-attachments --filters Name=transit-gateway-id,Values=${aws_ec2_transit_gateway.transit_gateway.id} --query 'TransitGatewayVpcAttachments[].[VpcId,State,SubnetIds]' --output json"
  description = "Command that shows each attachment and the subnets it was placed in. An attachment in a non-routable subnet is available and unreachable at the same time"
}
