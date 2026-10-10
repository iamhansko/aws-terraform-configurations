output "vpc_id" {
  value       = aws_vpc.vpc.id
  description = "ID of the VPC"
}
# Per-subnet outputs for a caller that needs one specific zone, and the array form for a caller that wants every
# public or every private subnet without assembling the list itself (rules.md C-3).
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
  description = "IDs of all private subnets, which hold the ElastiCache node and the VPC-attached Lambda ENIs"
}
output "nat_gateway_ids" {
  value       = [aws_nat_gateway.nat_gateway_a.id, aws_nat_gateway.nat_gateway_b.id]
  description = "IDs of the two zonal NAT gateways"
}
