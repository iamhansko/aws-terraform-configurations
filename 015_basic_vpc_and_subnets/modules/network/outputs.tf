output "vpc_id" {
  value       = aws_vpc.vpc.id
  description = "ID of the VPC"
}
output "vpc_cidr_block" {
  value       = aws_vpc.vpc.cidr_block
  description = "CIDR block of the VPC"
}
output "public_subnet_a_id" {
  value       = aws_subnet.public_subnet_a.id
  description = "ID of public subnet A"
}
output "public_subnet_b_id" {
  value       = aws_subnet.public_subnet_b.id
  description = "ID of public subnet B"
}
output "private_subnet_a_id" {
  value       = aws_subnet.private_subnet_a.id
  description = "ID of private subnet A"
}
output "private_subnet_b_id" {
  value       = aws_subnet.private_subnet_b.id
  description = "ID of private subnet B"
}
# Individual outputs above for a caller that needs one specific zone, list
# outputs below for one that needs them all (rules.md C-3).
output "public_subnet_ids" {
  value       = [aws_subnet.public_subnet_a.id, aws_subnet.public_subnet_b.id]
  description = "IDs of all public subnets"
}
output "private_subnet_ids" {
  value       = [aws_subnet.private_subnet_a.id, aws_subnet.private_subnet_b.id]
  description = "IDs of all private subnets"
}
output "public_subnet_cidr_blocks" {
  value       = [aws_subnet.public_subnet_a.cidr_block, aws_subnet.public_subnet_b.cidr_block]
  description = "CIDR blocks of the public subnets, in a/b order. Read from the subnets rather than recomputed with cidrsubnet, so this cannot disagree with what was actually created (rules.md B-5)"
}
output "private_subnet_cidr_blocks" {
  value       = [aws_subnet.private_subnet_a.cidr_block, aws_subnet.private_subnet_b.cidr_block]
  description = "CIDR blocks of the private subnets, in a/b order"
}
output "availability_zones" {
  value       = [aws_subnet.public_subnet_a.availability_zone, aws_subnet.public_subnet_b.availability_zone]
  description = "Availability zones the subnets span, in a/b order"
}
output "internet_gateway_id" {
  value       = aws_internet_gateway.internet_gateway.id
  description = "ID of the Internet Gateway the public route table sends 0.0.0.0/0 to"
}
output "nat_gateway_ids" {
  value       = [aws_nat_gateway.nat_gateway_a.id, aws_nat_gateway.nat_gateway_b.id]
  description = "IDs of the per-AZ NAT Gateways, in a/b order"
}
output "nat_gateway_public_ips" {
  value       = [aws_eip.nat_gateway_a_elastic_ip.public_ip, aws_eip.nat_gateway_b_elastic_ip.public_ip]
  description = "Elastic IPs the NAT Gateways egress from, in a/b order. These are the addresses a service outside the VPC sees when a private subnet reaches it, which is what makes them worth exposing"
}
output "public_route_table_id" {
  value       = aws_route_table.public_subnet_route_table.id
  description = "ID of the route table shared by both public subnets"
}
output "private_route_table_ids" {
  value       = [aws_route_table.private_subnet_a_route_table.id, aws_route_table.private_subnet_b_route_table.id]
  description = "IDs of the per-AZ private route tables, in a/b order. One per zone rather than one shared table, because each points at its own zone's NAT Gateway"
}
