output "vpc_id" {
  value       = aws_vpc.vpc.id
  description = "ID of the VPC"
}
output "vpc_cidr_block" {
  value       = aws_vpc.vpc.cidr_block
  description = "CIDR block of the VPC"
}
# Both shapes, as every network module in this repository exposes them (rules.md C-3): the single subnet for a
# caller that places one instance, and the list for a caller that takes "all public subnets" - so adding a
# second zone later changes nothing for the callers of the list.
output "public_subnet_a_id" {
  value       = aws_subnet.public_subnet_a.id
  description = "ID of the public subnet"
}
output "public_subnet_ids" {
  value       = [aws_subnet.public_subnet_a.id]
  description = "IDs of all public subnets - one, in this project"
}
output "availability_zone" {
  value       = aws_subnet.public_subnet_a.availability_zone
  description = "Zone the public subnet was placed in"
}
