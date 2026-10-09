output "vpc_id" {
  value       = aws_vpc.egress_vpc.id
  description = "ID of the egress VPC"
}
output "vpc_cidr_block" {
  value       = aws_vpc.egress_vpc.cidr_block
  description = "Primary CIDR block of the egress VPC"
}
output "internet_gateway_id" {
  value       = aws_internet_gateway.egress_igw.id
  description = "ID of the internet gateway. The only one in this project - the app VPC has none, which is what forces its traffic across the transit gateway"
}
output "public_subnet_ids" {
  value       = [for subnet in aws_subnet.public : subnet.id]
  description = "Public subnets, which hold the NAT gateways"
}
output "public_subnet_ids_by_zone" {
  value       = { for suffix, subnet in aws_subnet.public : suffix => subnet.id }
  description = "Public subnets keyed by zone suffix"
}
output "attachment_subnet_ids" {
  value       = [for subnet in aws_subnet.attachment : subnet.id]
  description = "Subnets the transit gateway attachment's ENIs go into. This is what the root passes to aws_ec2_transit_gateway_vpc_attachment - an attachment placed in the firewall or public tier instead would be created, report available, and route nothing"
}
output "attachment_subnet_ids_by_zone" {
  value       = { for suffix, subnet in aws_subnet.attachment : suffix => subnet.id }
  description = "Attachment subnets keyed by zone suffix"
}
output "firewall_subnet_ids_by_zone" {
  value       = { for suffix, subnet in aws_subnet.firewall : suffix => subnet.id }
  description = "Firewall subnets keyed by zone suffix, which is the shape the network_firewall module's subnet mapping needs: the keys are zone suffixes from configuration, so they are known during plan, while the subnet IDs are not (rules.md B-8)"
}
output "public_route_table_id" {
  value       = aws_route_table.public.id
  description = "ID of the public route table, re-exposed because the root writes one more route into it - the return route to the app VPC, which needs both this table and the transit gateway and therefore belongs to neither module (rules.md C-1)"
}
output "attachment_route_table_ids_by_zone" {
  value       = { for suffix, table in aws_route_table.attachment : suffix => table.id }
  description = "Per-zone route tables on the attachment subnets, keyed by zone suffix. These are the tables that would have to be repointed at the firewall endpoints to put the firewall in the data path"
}
output "nat_gateway_ids_by_zone" {
  value       = { for suffix, gateway in aws_nat_gateway.nat_gateway : suffix => gateway.id }
  description = "NAT gateways by zone suffix"
}
output "nat_gateway_public_ips" {
  value       = { for suffix, address in aws_eip.nat_gateway : suffix => address.public_ip }
  description = "The addresses the internet sees as the source of everything this project sends. A host in the app VPC asking an echo service for its own address should get one of these; getting its own 172.16 address back would mean it found some other way out"
}
output "availability_zones" {
  value       = [for suffix in var.availability_zone_suffixes : "${var.region}${suffix}"]
  description = "Full zone names this VPC spans"
}
output "route_tables_command" {
  value       = "aws ec2 describe-route-tables --filters Name=vpc-id,Values=${aws_vpc.egress_vpc.id} --query 'RouteTables[].{Name:Tags[?Key==`Name`].Value|[0],Routes:Routes[].[DestinationCidrBlock,GatewayId,NatGatewayId,TransitGatewayId,VpcEndpointId]}' --output json"
  description = "Every route table in the egress VPC with its routes. Three tables appear, not four: the firewall subnets have no table of their own and are therefore absent, which is the quickest way to see that the firewall is not in the data path"
}
output "nat_gateway_check_command" {
  value       = "aws ec2 describe-nat-gateways --filter Name=vpc-id,Values=${aws_vpc.egress_vpc.id} --query 'NatGateways[].[NatGatewayId,State,SubnetId,NatGatewayAddresses[0].PublicIp]' --output table"
  description = "State of both NAT gateways. A gateway stuck in failed state was created before the internet gateway was attached, and that state is terminal - it does not recover once the attachment lands (rules.md D-1)"
}
