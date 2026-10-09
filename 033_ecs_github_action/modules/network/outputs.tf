output "vpc_id" {
  value       = aws_vpc.vpc.id
  description = "ID of the VPC"
}
output "vpc_cidr_block" {
  value       = aws_vpc.vpc.cidr_block
  description = "CIDR block of the VPC, for security group rules that should reach everything inside it and nothing outside - the ALB's egress to the task ENIs is one"
}
# The VPC's own default security group, which the _monolithic template used as an ingress source on both the
# container instance group and the service group. Nothing in this project is launched into it, so those
# rules admit nothing as built; they are reproduced because the original declared them, and exposing the ID
# here is what lets the root pass it in as a labelled map entry rather than having a module look it up
# (rules.md B-6/B-8).
output "default_security_group_id" {
  value       = aws_vpc.vpc.default_security_group_id
  description = "ID of the VPC's default security group"
}
# Per-subnet outputs for a caller that needs one specific zone, and the array form for a caller that wants
# every public or every private subnet without assembling the list itself (rules.md C-3).
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
  description = "IDs of all public subnets, which is what the internet-facing ALB spans"
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
  description = "IDs of all private subnets, which hold both the container instances and the awsvpc task ENIs"
}
output "availability_zones" {
  value       = [aws_subnet.private_subnet_a.availability_zone, aws_subnet.private_subnet_b.availability_zone]
  description = "Availability zones the subnet pairs span, re-exposed so a caller can report them without rebuilding region plus letter (rules.md B-5)"
}
output "nat_gateway_ids" {
  value       = [aws_nat_gateway.nat_gateway_a.id, aws_nat_gateway.nat_gateway_b.id]
  description = "IDs of the two zonal NAT gateways carrying outbound traffic for the private subnets"
}
output "nat_gateway_public_ips" {
  value       = [aws_eip.nat_gateway_elastic_ip_a.public_ip, aws_eip.nat_gateway_elastic_ip_b.public_ip]
  description = "The addresses the container instances and tasks appear as from outside. Docker Hub rate-limits anonymous pulls by source address, and these are the addresses it counts"
}
