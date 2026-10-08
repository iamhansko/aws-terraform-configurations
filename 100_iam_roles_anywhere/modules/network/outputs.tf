output "vpc_id" {
  value       = aws_vpc.vpc.id
  description = "ID of the VPC"
}
output "vpc_cidr_block" {
  value       = aws_vpc.vpc.cidr_block
  description = "CIDR block of the VPC"
}
output "public_subnet_id" {
  value       = aws_subnet.public_subnet.id
  description = "ID of the public subnet, for a caller that needs one specific subnet"
}
# The array form as well as the individual one, so a caller that wants "every public subnet" does
# not assemble the list itself (rules.md C-3). It holds a single element here because the project
# runs one instance in one zone; the name matches the multi-zone networks elsewhere in this
# repository, so adding a zone later does not change caller code.
output "public_subnet_ids" {
  value       = [aws_subnet.public_subnet.id]
  description = "IDs of all public subnets"
}
output "availability_zones" {
  value       = [aws_subnet.public_subnet.availability_zone]
  description = "Availability zones the subnets span"
}
output "internet_gateway_id" {
  value       = aws_internet_gateway.internet_gateway.id
  description = "ID of the internet gateway"
}
output "public_route_table_id" {
  value       = aws_route_table.public_subnet_route_table.id
  description = "ID of the public route table"
}
