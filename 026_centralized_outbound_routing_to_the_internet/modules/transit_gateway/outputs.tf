output "transit_gateway_id" {
  value       = aws_ec2_transit_gateway.transit_gateway.id
  description = "ID of the transit gateway. Both VPC default routes and both attachments point at this"
}
output "transit_gateway_arn" {
  value       = aws_ec2_transit_gateway.transit_gateway.arn
  description = "ARN of the transit gateway"
}
# This output is the whole reason an entire Lambda function, an IAM role, an inline ec2:* policy, a
# managed policy attachment, an archive_file, an aws_lambda_invocation and the archive provider are
# absent from this project.
#
# The _monolithic template needed the id of the route table AWS creates and auto-associates when
# default_route_table_association is enabled, because that is the table its one static route had to
# go into. CloudFormation cannot read it, so the template carried a custom resource whose handler
# called ec2:DescribeTransitGateways and returned Options.AssociationDefaultRouteTableId. The AWS
# provider surfaces the same field as an attribute of the gateway, so the lookup is a reference.
#
# The converted function could not have returned it in any case, for four independent reasons, each
# of them fatal on its own:
#
#   1. index.py imports cfnresponse. AWS injects that module only into functions whose code was
#      inlined in the template as ZipFile; a package built by archive_file does not get it, so the
#      handler fails at import with ModuleNotFoundError before running a line.
#   2. It reads event["ResourceProperties"]["TransitGatewayId"]. aws_lambda_invocation sends exactly
#      the input document it is given, which had TransitGatewayId at the top level - so this is a
#      KeyError even with cfnresponse vendored in.
#   3. It reports by calling cfnresponse.send(...), which POSTs the result to event["ResponseURL"].
#      There is no ResponseURL in a payload Terraform sends, and no CloudFormation endpoint waiting
#      on one.
#   4. aws_lambda_invocation reads the function's return value. This handler returns None, so
#      jsondecode(...)["DefaultRouteTableId"] in the original would have been decoding "null".
#
# lambda_src/custom_resource_lambda_function/index.py is still on disk and nothing references it. It
# is left there as the evidence for the four points above; deleting it would leave this comment
# describing a file nobody can check.
output "association_default_route_table_id" {
  value       = aws_ec2_transit_gateway.transit_gateway.association_default_route_table_id
  description = "ID of the route table AWS created and auto-associated both attachments with, because default_route_table_association is enabled. The root's static default route goes into this table. Replaces the _monolithic template's DescribeTransitGateways Lambda custom resource outright - see the comment above this output"
}
output "propagation_default_route_table_id" {
  value       = aws_ec2_transit_gateway.transit_gateway.propagation_default_route_table_id
  description = "ID of the table attachments propagate their VPC CIDRs into. The same table as above with these settings, and it is where the app VPC's 172.16.0.0/16 return route comes from - that route is installed by AWS, so it appears in no plan and its absence would look like a firewall problem rather than a routing one"
}
output "routes_check_command" {
  value       = "aws ec2 search-transit-gateway-routes --transit-gateway-route-table-id ${aws_ec2_transit_gateway.transit_gateway.association_default_route_table_id} --filters Name=state,Values=active,blackhole --query 'Routes[].[DestinationCidrBlock,Type,State,TransitGatewayAttachments[0].ResourceId]' --output table"
  description = "The gateway's routes. Two rows are expected: a static 0.0.0.0/0 pointing at the egress VPC's attachment, and a propagated 172.16.0.0/16 pointing at the app VPC's. A row in blackhole state is this project's worst failure mode - it exists, so nothing errors, and every packet matching it is dropped"
}
output "attachments_check_command" {
  value       = "aws ec2 describe-transit-gateway-vpc-attachments --filters Name=transit-gateway-id,Values=${aws_ec2_transit_gateway.transit_gateway.id} --query 'TransitGatewayVpcAttachments[].[Tags[?Key==`Name`].Value|[0],VpcId,State,SubnetIds]' --output json"
  description = "Each attachment and the subnets it was placed in. Worth checking the subnet IDs rather than just the state: an attachment in the egress VPC's firewall or public tier reports available and routes nothing, because the route table that sends traffic onward to a NAT gateway is on the attachment tier only"
}
