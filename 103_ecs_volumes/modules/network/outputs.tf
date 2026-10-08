output "vpc_id" {
  value       = aws_vpc.vpc.id
  description = "ID of the VPC"
}
output "vpc_cidr_block" {
  value       = aws_vpc.vpc.cidr_block
  description = "CIDR block of the VPC"
}
# Per-subnet outputs for a caller that needs one specific zone, and the array form for a caller that
# wants "every public subnet" or "every private subnet" without assembling the list itself (rules.md
# C-3). Both shapes exist whatever the zone count, so adding a zone later does not change caller code -
# the image builder keeps reading public_subnet_a_id and the Auto Scaling group keeps reading
# private_subnet_ids.
output "public_subnet_a_id" {
  value       = aws_subnet.public_subnet_a.id
  description = "ID of the public subnet in the first zone, which is where the image builder is launched"
}
output "public_subnet_c_id" {
  value       = aws_subnet.public_subnet_c.id
  description = "ID of the public subnet in the second zone"
}
output "public_subnet_ids" {
  value       = [aws_subnet.public_subnet_a.id, aws_subnet.public_subnet_c.id]
  description = "IDs of all public subnets"
}
output "private_subnet_a_id" {
  value       = aws_subnet.private_subnet_a.id
  description = "ID of the private subnet in the first zone"
}
output "private_subnet_c_id" {
  value       = aws_subnet.private_subnet_c.id
  description = "ID of the private subnet in the second zone"
}
output "private_subnet_ids" {
  value       = [aws_subnet.private_subnet_a.id, aws_subnet.private_subnet_c.id]
  description = "IDs of all private subnets, which is what the container instance Auto Scaling group spans. Its order matches availability_zones"
}
output "availability_zones" {
  value       = [aws_subnet.private_subnet_a.availability_zone, aws_subnet.private_subnet_c.availability_zone]
  description = "Availability zones the subnet pairs span, re-exposed so a caller can report them without rebuilding region plus letter (rules.md B-5)"
}
output "internet_gateway_id" {
  value       = aws_internet_gateway.internet_gateway.id
  description = "ID of the internet gateway"
}
output "nat_gateway_id" {
  value       = aws_nat_gateway.nat_gateway.id
  description = "ID of the regional NAT gateway carrying the container instances' outbound traffic"
}
output "nat_gateway_public_ips" {
  value       = [aws_eip.nat_gateway_elastic_ip_a.public_ip, aws_eip.nat_gateway_elastic_ip_c.public_ip]
  description = "The addresses the container instances appear as from outside. Worth having when a pull from a registry outside AWS is being rate limited by source address"
}
output "public_route_table_id" {
  value       = aws_route_table.public_subnet_route_table.id
  description = "ID of the public route table"
}
output "private_route_table_id" {
  value       = aws_route_table.private_subnet_route_table.id
  description = "ID of the private route table, which carries the single default route to the regional NAT gateway"
}
