output "vpc_id" {
  value       = aws_vpc.vpc.id
  description = "ID of the VPC"
}
output "vpc_cidr_block" {
  value       = aws_vpc.vpc.cidr_block
  description = "CIDR block of the VPC, re-exposed so a rule admitting in-VPC traffic does not restate it (rules.md B-5)"
}
output "availability_zones" {
  value       = local.zones
  description = "The three zones the subnets were placed in, in the order the per-zone outputs below use (a, b, c)"
}
# Per-zone outputs and the list forms together (rules.md C-3). The letters name positions in
# availability_zones rather than zone names, because the zones come from the region's list and are
# not necessarily the ones ending in a, b and c.
output "public_subnet_a_id" {
  value       = aws_subnet.public[local.zones[0]].id
  description = "ID of the public subnet in the first zone - the workbench's subnet, and the NAT gateway's"
}
output "public_subnet_b_id" {
  value       = aws_subnet.public[local.zones[1]].id
  description = "ID of the public subnet in the second zone"
}
output "public_subnet_c_id" {
  value       = aws_subnet.public[local.zones[2]].id
  description = "ID of the public subnet in the third zone"
}
output "private_subnet_a_id" {
  value       = aws_subnet.private[local.zones[0]].id
  description = "ID of the private subnet in the first zone"
}
output "private_subnet_b_id" {
  value       = aws_subnet.private[local.zones[1]].id
  description = "ID of the private subnet in the second zone"
}
output "private_subnet_c_id" {
  value       = aws_subnet.private[local.zones[2]].id
  description = "ID of the private subnet in the third zone"
}
output "public_subnet_ids" {
  value       = [for zone in local.zones : aws_subnet.public[zone].id]
  description = "IDs of all public subnets, in availability_zones order"
}
output "private_subnet_ids" {
  value       = [for zone in local.zones : aws_subnet.private[zone].id]
  description = "IDs of all private subnets, in availability_zones order - so slice(..., 0, 2) is always the first two zones"
}
output "private_route_table_ids" {
  value       = [aws_route_table.private.id]
  description = "IDs of the private route tables. One element, because one NAT gateway serves all three private subnets; a list so a gateway endpoint takes it as-is if the network grows a NAT gateway per zone"
}
output "nat_gateway_public_ip" {
  value       = aws_eip.nat_gateway.public_ip
  description = "Public address every outbound connection from the private subnets leaves from - the nodes, the pods and MWAA's workers alike"
}
