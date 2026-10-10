output "vpc_id" {
  value       = aws_vpc.vpc.id
  description = "ID of the VPC"
}
# The single-subnet output and the array form together, as every network module here exposes them, so a
# second zone could be added later without changing callers (rules.md C-3).
output "public_subnet_a_id" {
  value       = aws_subnet.public_subnet_a.id
  description = "ID of the public subnet, which is where the VS Code instance is launched"
}
output "public_subnet_ids" {
  value       = [aws_subnet.public_subnet_a.id]
  description = "IDs of all public subnets"
}
