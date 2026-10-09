output "vpc_id" {
  value       = aws_vpc.app_vpc.id
  description = "ID of the spoke VPC. The workbench module needs it for its security group, and the root needs it for this VPC's transit gateway attachment"
}
output "vpc_cidr_block" {
  value       = aws_vpc.app_vpc.cidr_block
  description = "CIDR of the spoke VPC, handed back out because the egress VPC's return route is written against exactly this value - taking it from here rather than restating 172.16.0.0/16 is what stops the route and the VPC disagreeing (rules.md B-5)"
}
output "availability_zone_a" {
  value       = var.availability_zone_a
  description = "First zone, returned as passed in, so the root can compare it against the egress VPC's first zone (rules.md B-5)"
}
output "availability_zone_b" {
  value       = var.availability_zone_b
  description = "Second zone, returned as passed in (rules.md B-5)"
}
output "private_subnet_a_id" {
  value       = aws_subnet.app_private_subnet_a.id
  description = "ID of the zone a private subnet. The workbench instance is launched here, which is why the address a curl from it reports should be the zone a NAT gateway's"
}
output "private_subnet_b_id" {
  value       = aws_subnet.app_private_subnet_b.id
  description = "ID of the zone b private subnet. Nothing is launched in it; it exists so the transit gateway attachment is available in both zones, which is what makes the second firewall endpoint and the second NAT gateway reachable"
}
output "private_subnet_ids" {
  value       = [aws_subnet.app_private_subnet_a.id, aws_subnet.app_private_subnet_b.id]
  description = "Both private subnets as a list, which is the form the transit gateway attachment's subnet_ids takes (rules.md C-3)"
}
output "route_table_id" {
  value       = aws_route_table.app_rt.id
  description = "ID of the route table shared by both subnets, exposed so the root can add the 0.0.0.0/0 route to the transit gateway without this module learning that a transit gateway exists (rules.md C-1)"
}
