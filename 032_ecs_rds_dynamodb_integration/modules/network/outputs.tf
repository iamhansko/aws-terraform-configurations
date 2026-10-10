output "vpc_id" {
  value       = aws_vpc.vpc.id
  description = "ID of the VPC"
}
output "vpc_cidr_block" {
  value       = aws_vpc.vpc.cidr_block
  description = "CIDR block of the VPC, for security group rules that should reach anything inside it and nothing outside"
}
# Per-subnet outputs for a caller that needs one specific zone, and the array form for a caller that wants
# every public or every private subnet without assembling the list itself (rules.md C-3).
output "public_subnet_a_id" {
  value       = aws_subnet.public_subnet_a.id
  description = "ID of the public subnet in the first zone, which is where the workbench instance is launched"
}
output "public_subnet_b_id" {
  value       = aws_subnet.public_subnet_b.id
  description = "ID of the public subnet in the second zone"
}
output "public_subnet_ids" {
  value       = [aws_subnet.public_subnet_a.id, aws_subnet.public_subnet_b.id]
  description = "IDs of all public subnets"
}
output "private_subnet_a_id" {
  value       = aws_subnet.private_subnet_a.id
  description = "ID of the private subnet in the first zone"
}
output "private_subnet_b_id" {
  value       = aws_subnet.private_subnet_b.id
  description = "ID of the private subnet in the second zone"
}
output "private_subnet_ids" {
  value       = [aws_subnet.private_subnet_a.id, aws_subnet.private_subnet_b.id]
  description = "IDs of all private subnets, which is where the container instances, the awsvpc task ENIs and the DB subnet group all live"
}
output "availability_zones" {
  value       = [aws_subnet.private_subnet_a.availability_zone, aws_subnet.private_subnet_b.availability_zone]
  description = "The zones the subnet pairs span, read back off the subnets rather than rebuilt from region plus letter (rules.md B-5)"
}
output "nat_gateway_ids" {
  value       = [aws_nat_gateway.nat_gateway_a.id, aws_nat_gateway.nat_gateway_b.id]
  description = "IDs of the per-zone NAT gateways carrying all outbound traffic from the private subnets"
}
output "nat_gateway_public_ips" {
  value       = [aws_eip.nat_gateway_elastic_ip_a.public_ip, aws_eip.nat_gateway_elastic_ip_b.public_ip]
  description = "The addresses the container instances and tasks appear as from outside. Public registries rate-limit anonymous pulls by source address, and these are the addresses counted"
}
