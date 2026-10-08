output "vpc_id" {
  value       = aws_vpc.vpc.id
  description = "ID of the VPC"
}
output "vpc_cidr_block" {
  value       = aws_vpc.vpc.cidr_block
  description = "CIDR of the VPC, re-exposed so a caller writing a security group rule scoped to the VPC does not restate the value the root already passed in (rules.md B-5)"
}
output "public_subnet_a_id" {
  value       = aws_subnet.public_subnet_a.id
  description = "ID of the one public subnet, for a caller that needs that zone specifically"
}
output "public_subnet_ids" {
  value       = [aws_subnet.public_subnet_a.id]
  description = "All public subnets as a list. One element here, but the name does not change with the zone count, so a caller keeps working if a second zone is ever added (rules.md C-3)"
}
output "public_subnet_cidr_blocks" {
  value       = [aws_subnet.public_subnet_a.cidr_block]
  description = "CIDRs the subnets were actually carved to. Derived from vpc_cidr_block by cidrsubnet, so this is the only place the resulting value is visible"
}
output "availability_zone" {
  value       = aws_subnet.public_subnet_a.availability_zone
  description = "Zone the public subnet landed in, resolved from the region and the suffix"
}
output "route_table_id" {
  value       = aws_route_table.public_subnet_route_table.id
  description = "ID of the public route table, for a caller adding a route or a gateway endpoint"
}
# The VPC's default security group is deliberately not exposed.
#
# The _monolithic template attached it to the instance (vpc_security_group_ids =
# [aws_vpc.vpc.default_security_group_id]) and declared no group of its own. That group allows all traffic
# from itself and all traffic outbound, so it worked - but it is shared by anything else launched in the
# VPC, it is not described by this configuration, and Terraform does not manage its rules here. The seeder
# module builds its own group instead, and not offering this output is what stops the next reader
# reattaching the default one.
