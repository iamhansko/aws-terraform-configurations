output "vpc_id" {
  value       = aws_vpc.vpc.id
  description = "ID of the VPC"
}
output "vpc_cidr_block" {
  value       = aws_vpc.vpc.cidr_block
  description = "CIDR block of the VPC, for security group rules that should reach anything inside it and nothing outside"
}
# Per-subnet outputs for a caller that needs one specific zone, and the array form for a caller that wants
# "every public subnet" or "every private subnet" without assembling the list itself (rules.md C-3).
output "public_subnet_a_id" {
  value       = aws_subnet.public_subnet_a.id
  description = "ID of the public subnet in the first zone, which is where the VS Code instance is launched"
}
output "public_subnet_c_id" {
  value       = aws_subnet.public_subnet_c.id
  description = "ID of the public subnet in the second zone"
}
output "public_subnet_ids" {
  value       = [aws_subnet.public_subnet_a.id, aws_subnet.public_subnet_c.id]
  description = "IDs of all public subnets, which is what the internet-facing ALB spans"
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
  description = "IDs of all private subnets, which is where the Fargate tasks are placed"
}
output "availability_zones" {
  value       = [aws_subnet.private_subnet_a.availability_zone, aws_subnet.private_subnet_c.availability_zone]
  description = "Availability zones the subnet pairs span, re-exposed so a caller can report them without rebuilding region plus letter (rules.md B-5)"
}
output "nat_gateway_id" {
  value       = aws_nat_gateway.nat_gateway.id
  description = "ID of the regional NAT gateway carrying the tasks' outbound traffic"
}
output "nat_gateway_public_ips" {
  value       = [aws_eip.nat_gateway_elastic_ip_a.public_ip, aws_eip.nat_gateway_elastic_ip_c.public_ip]
  description = "The addresses the tasks appear as from outside. Docker Hub rate-limits anonymous pulls by source address, and these are the addresses it counts"
}
