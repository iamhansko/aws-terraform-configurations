# Plain outputs here, rather than the local.outputs map the projects with a
# code-server instance use. That pattern exists to keep a README rendered onto the
# instance in step with outputs.tf (rules.md H-2); this project creates no
# instance, so there is no second copy of these values to drift from.
#
# Every value is a module output rather than an expression rebuilt here, so
# nothing in this file can disagree with what the module created (rules.md B-5).
output "vpc_id" {
  value       = module.network.vpc_id
  description = "ID of the VPC"
}
output "vpc_cidr_block" {
  value       = module.network.vpc_cidr_block
  description = "CIDR block of the VPC"
}
output "availability_zones" {
  value       = module.network.availability_zones
  description = "Availability zones the subnets span, in a/b order"
}
output "public_subnet_ids" {
  value       = module.network.public_subnet_ids
  description = "IDs of the public subnets, in a/b order"
}
output "private_subnet_ids" {
  value       = module.network.private_subnet_ids
  description = "IDs of the private subnets, in a/b order"
}
output "public_subnet_cidr_blocks" {
  value       = module.network.public_subnet_cidr_blocks
  description = "CIDR blocks of the public subnets, in a/b order"
}
output "private_subnet_cidr_blocks" {
  value       = module.network.private_subnet_cidr_blocks
  description = "CIDR blocks of the private subnets, in a/b order"
}
output "internet_gateway_id" {
  value       = module.network.internet_gateway_id
  description = "ID of the Internet Gateway, the target of the public subnets' 0.0.0.0/0 route"
}
output "nat_gateway_ids" {
  value       = module.network.nat_gateway_ids
  description = "IDs of the per-AZ NAT Gateways, in a/b order"
}
output "nat_gateway_public_ips" {
  value       = module.network.nat_gateway_public_ips
  description = "Elastic IPs the private subnets egress from, in a/b order. An outside service sees one of these as the source address of traffic from a private subnet"
}
output "public_route_table_id" {
  value       = module.network.public_route_table_id
  description = "ID of the route table shared by both public subnets"
}
output "private_route_table_ids" {
  value       = module.network.private_route_table_ids
  description = "IDs of the per-AZ private route tables, in a/b order"
}
# The topology is the deliverable, so the checks that show it are outputs too.
# Nothing here is a Terraform value: they are commands to run against what was
# created, the way the projects with an instance put verification commands in
# their README (rules.md H-2).
output "describe_subnets_command" {
  value       = "aws ec2 describe-subnets --region ${data.aws_region.current.region} --filters Name=vpc-id,Values=${module.network.vpc_id} --query 'Subnets[].{Name:Tags[?Key==`Name`]|[0].Value,AZ:AvailabilityZone,Cidr:CidrBlock,PublicIP:MapPublicIpOnLaunch}' --output table"
  description = "Lists the four subnets with their zone, CIDR and public-IP behaviour - the one command that shows the whole layout at once"
}
output "describe_route_tables_command" {
  value       = "aws ec2 describe-route-tables --region ${data.aws_region.current.region} --filters Name=vpc-id,Values=${module.network.vpc_id} --query 'RouteTables[].{Name:Tags[?Key==`Name`]|[0].Value,Routes:Routes[].join(` -> `,[DestinationCidrBlock,not_null(GatewayId,NatGatewayId)])}' --output table"
  description = "Shows which gateway each route table sends 0.0.0.0/0 to: the Internet Gateway for the public table, that zone's NAT Gateway for each private table. This is the difference between a public and a private subnet"
}
