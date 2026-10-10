output "vpc_id" {
  value       = aws_vpc.vpc.id
  description = "ID of the VPC"
}
output "vpc_cidr_block" {
  value       = aws_vpc.vpc.cidr_block
  description = "CIDR block of the VPC"
}
# Per-subnet outputs for a caller that needs one specific zone, and the array form for a caller that
# wants every public or every private subnet without assembling the list itself (rules.md C-3). Both
# shapes exist whatever the zone count, so adding a zone later would not change caller code - the
# bastion keeps reading public_subnet_a_id and the load balancer keeps reading public_subnet_ids.
output "public_subnet_a_id" {
  value       = aws_subnet.public_subnet_a.id
  description = "ID of the public subnet in the first zone, which is where the bastion builder is launched"
}
output "public_subnet_b_id" {
  value       = aws_subnet.public_subnet_b.id
  description = "ID of the public subnet in the second zone"
}
output "public_subnet_ids" {
  value       = [aws_subnet.public_subnet_a.id, aws_subnet.public_subnet_b.id]
  description = "IDs of all public subnets, which is what the internet-facing Application Load Balancer spans"
}
output "private_subnet_a_id" {
  value       = aws_subnet.private_subnet_a.id
  description = "ID of the private subnet in the first zone"
}
output "private_subnet_b_id" {
  value       = aws_subnet.private_subnet_b.id
  description = "ID of the private subnet in the second zone"
}
output "private_subnet_ids" {
  value       = [aws_subnet.private_subnet_a.id, aws_subnet.private_subnet_b.id]
  description = "IDs of all private subnets. The container instance Auto Scaling group spans these, and so do the task network interfaces. Order matches availability_zones"
}
output "availability_zones" {
  value       = [aws_subnet.private_subnet_a.availability_zone, aws_subnet.private_subnet_b.availability_zone]
  description = "Zones the subnet pairs span, re-exposed so a caller can report them without rebuilding region plus letter (rules.md B-5)"
}
output "internet_gateway_id" {
  value       = aws_internet_gateway.internet_gateway.id
  description = "ID of the internet gateway"
}
output "nat_gateway_ids" {
  value       = [aws_nat_gateway.nat_gateway_a.id, aws_nat_gateway.nat_gateway_b.id]
  description = "IDs of the two zonal NAT gateways, one per private subnet"
}
output "nat_gateway_public_ips" {
  value       = [aws_eip.nat_gateway_a_elastic_ip.public_ip, aws_eip.nat_gateway_b_elastic_ip.public_ip]
  description = "The addresses the container instances and the tasks appear as from outside. Worth having when a pull from a registry outside AWS is being rate limited by source address"
}
output "public_route_table_id" {
  value       = aws_route_table.public_subnet_route_table.id
  description = "ID of the public route table"
}
output "private_route_table_ids" {
  value       = [aws_route_table.private_subnet_a_route_table.id, aws_route_table.private_subnet_b_route_table.id]
  description = "IDs of the two private route tables, each carrying one default route to its own zone's NAT gateway"
}
output "route_tables_command" {
  value       = "aws ec2 describe-route-tables --filters Name=vpc-id,Values=${aws_vpc.vpc.id} --query 'RouteTables[].[Tags[?Key==`Name`].Value|[0],Routes[].{To:DestinationCidrBlock,Via:join(``,[GatewayId,NatGatewayId])}]' --output json"
  description = "Command printing every route table in the VPC with its routes. This is where the two-zone egress design is visible: one public table to the internet gateway and one private table per zone to that zone's NAT gateway"
}
