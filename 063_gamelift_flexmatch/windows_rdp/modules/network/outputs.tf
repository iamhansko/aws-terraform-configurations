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
  description = "ID of the public subnet in the first zone, which holds the Windows instance"
}
output "public_subnet_c_id" {
  value       = aws_subnet.public_subnet_c.id
  description = "ID of the public subnet in the second zone"
}
output "private_subnet_a_id" {
  value       = aws_subnet.private_subnet_a.id
  description = "ID of the private subnet in the first zone"
}
output "private_subnet_c_id" {
  value       = aws_subnet.private_subnet_c.id
  description = "ID of the private subnet in the second zone"
}
output "public_subnet_ids" {
  value       = [aws_subnet.public_subnet_a.id, aws_subnet.public_subnet_c.id]
  description = "IDs of both public subnets, zone a first"
}
output "private_subnet_ids" {
  value       = [aws_subnet.private_subnet_a.id, aws_subnet.private_subnet_c.id]
  description = "IDs of both private subnets, zone a first"
}
output "availability_zones" {
  value       = [local.availability_zone_a, local.availability_zone_c]
  description = "The two zones the subnets were placed in, in the same order as the *_subnet_ids outputs"
}
