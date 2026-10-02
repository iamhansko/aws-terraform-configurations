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
output "public_subnet_ids" {
  value       = [aws_subnet.public_subnet_a.id, aws_subnet.public_subnet_b.id]
  description = "IDs of all public subnets"
}
output "private_subnet_ids" {
  value       = [aws_subnet.private_subnet_a.id, aws_subnet.private_subnet_b.id]
  description = "IDs of all private subnets"
}
output "availability_zones" {
  value       = [aws_subnet.public_subnet_a.availability_zone, aws_subnet.public_subnet_b.availability_zone]
  description = "Availability zones the subnets span, in a/b order"
}
output "private_subnet_cidr_blocks" {
  value = {
    a = aws_subnet.private_subnet_a.cidr_block
    b = aws_subnet.private_subnet_b.cidr_block
  }
  description = "CIDR block of each private subnet, keyed by AZ letter. Exposed so a caller can state how much address space the nodes actually have without restating the arithmetic that produced it (rules.md B-5)"
}
output "nat_gateway_ids" {
  value = {
    a = aws_nat_gateway.nat_gateway_a.id
    b = aws_nat_gateway.nat_gateway_b.id
  }
  description = "NAT Gateway ID for each AZ, keyed by AZ letter. A map rather than a list because callers route additional subnets through these per zone, and for_each needs keys that are known during plan while these IDs are not (rules.md B-8)"
}
