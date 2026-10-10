output "vpc_id" {
  value       = aws_vpc.vpc.id
  description = "ID of the VPC"
}
output "vpc_cidr_block" {
  value       = aws_vpc.vpc.cidr_block
  description = "CIDR block of the VPC, for security group rules that should reach anything inside it and nothing outside"
}
# Per-subnet outputs for a caller that needs one specific zone, and the array form for a caller that wants
# every public subnet without assembling the list itself (rules.md C-3).
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
  description = "IDs of all public subnets, which is what the container instance Auto Scaling group spans. This VPC has no private subnets at all - the comment at the top of the module's main.tf says why"
}
output "availability_zones" {
  value       = [aws_subnet.public_subnet_a.availability_zone, aws_subnet.public_subnet_b.availability_zone]
  description = "Availability zones the subnets span, re-exposed so a caller can report them without rebuilding region plus letter (rules.md B-5)"
}
output "internet_gateway_id" {
  value       = aws_internet_gateway.internet_gateway.id
  description = "ID of the internet gateway, which is the only outbound path in this VPC"
}
