output "vpc_id" {
  value       = aws_vpc.vpc.id
  description = "ID of the VPC"
}

output "public_subnet_a_id" {
  value       = aws_subnet.public_subnet_a.id
  description = "ID of the public subnet containing the NAT gateway"
}

output "public_subnet_ids" {
  value       = [aws_subnet.public_subnet_a.id]
  description = "IDs of all public subnets"
}

output "private_subnet_a_id" {
  value       = aws_subnet.private_subnet_a.id
  description = "ID of the private subnet containing the bootstrap instance"
}

output "private_subnet_ids" {
  value       = [aws_subnet.private_subnet_a.id]
  description = "IDs of all private subnets"
}

output "nat_gateway_id" {
  value       = aws_nat_gateway.bootstrap.id
  description = "ID of the NAT gateway that provides BPA-compatible bootstrap egress"
}

output "nat_gateway_public_ip" {
  value       = aws_eip.nat_gateway.public_ip
  description = "Public egress IPv4 address of the NAT gateway"
}
