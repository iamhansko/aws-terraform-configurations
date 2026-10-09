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
output "public_subnet_c_id" {
  value       = aws_subnet.public_subnet_c.id
  description = "ID of the public subnet in the second zone"
}
output "public_subnet_ids" {
  value       = [aws_subnet.public_subnet_a.id, aws_subnet.public_subnet_c.id]
  description = "IDs of both public subnets, which is what the internet-facing ALB spans and where the Fargate tasks are placed"
}
output "availability_zones" {
  value       = [aws_subnet.public_subnet_a.availability_zone, aws_subnet.public_subnet_c.availability_zone]
  description = "Zones the subnets are in, read back off the subnets rather than rebuilt from region plus letter (rules.md B-5)"
}
