output "vpc_id" {
  value       = aws_vpc.vpc.id
  description = "ID of the VPC, which the instance modules need for their security groups"
}
output "vpc_cidr_block" {
  value       = aws_vpc.vpc.cidr_block
  description = "CIDR of the VPC, re-exposed so a caller narrowing a security group to in-VPC traffic does not restate it (rules.md B-5)"
}
output "public_subnet_a_id" {
  value       = aws_subnet.public_subnet_a.id
  description = "ID of the public subnet both instances are launched in"
}
output "public_subnet_ids" {
  value       = [aws_subnet.public_subnet_a.id]
  description = "Every public subnet as a list. One element today, because this project runs in one availability zone; the list form exists so a caller that wants all of them does not have to change when a second zone is added (rules.md C-3)"
}
output "public_route_table_id" {
  value       = aws_route_table.public_route_table.id
  description = "ID of the public route table, for adding routes - a VPC endpoint or a peering route - from the root without this module changing"
}
