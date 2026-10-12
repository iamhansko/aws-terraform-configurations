output "vpc_id" {
  value       = aws_vpc.this.id
  description = "ID of the workbench VPC."
}

output "public_subnet_a_id" {
  value       = aws_subnet.public_a.id
  description = "ID of the public subnet used by the workbench."
}

output "public_subnet_ids" {
  value       = [aws_subnet.public_a.id]
  description = "IDs of all public subnets, alongside the individual output (rules.md C-3)."
}
