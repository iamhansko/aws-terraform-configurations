output "vpc_id" {
  value       = aws_vpc.vpc.id
  description = "ID of the VPC, which the workbench's security group is created in"
}
output "vpc_cidr_block" {
  value       = aws_vpc.vpc.cidr_block
  description = "CIDR block of the VPC, re-exposed so a caller narrowing a rule to in-VPC traffic does not restate it (rules.md B-5)"
}
output "public_subnet_id" {
  value       = aws_subnet.public_subnet.id
  description = "ID of the public subnet the workbench and the test instances are launched into"
}
# The list form as well as the individual one (rules.md C-3). One element, because this project runs
# in one availability zone; the name matches the multi-zone networks elsewhere in this repository, so
# a caller that wants every public subnet does not change if a zone is added.
output "public_subnet_ids" {
  value       = [aws_subnet.public_subnet.id]
  description = "IDs of all public subnets"
}
output "availability_zone" {
  value       = aws_subnet.public_subnet.availability_zone
  description = "Availability zone of the public subnet"
}
output "public_route_table_id" {
  value       = aws_route_table.public_route_table.id
  description = "ID of the public route table, for adding a route - a VPC endpoint or a peering connection - from the root without this module changing"
}
