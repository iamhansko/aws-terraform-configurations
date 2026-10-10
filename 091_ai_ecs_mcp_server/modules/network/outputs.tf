output "vpc_id" {
  value       = aws_vpc.vpc.id
  description = "ID of the VPC"
}
output "vpc_cidr_block" {
  value       = aws_vpc.vpc.cidr_block
  description = "CIDR block of the VPC, for security group rules that should reach anything inside it and nothing outside"
}
# Per-zone outputs for a caller that needs one specific zone, the array form for a caller that wants all of
# them, and the by-zone map for a caller that has to for_each over them with keys known at plan (rules.md
# B-8/C-3).
output "public_subnet_a_id" {
  value       = aws_subnet.public[var.availability_zone_suffixes[0]].id
  description = "ID of the public subnet in the first zone"
}
output "public_subnet_b_id" {
  value       = aws_subnet.public[var.availability_zone_suffixes[1]].id
  description = "ID of the public subnet in the second zone"
}
output "public_subnet_ids" {
  value       = [for suffix in var.availability_zone_suffixes : aws_subnet.public[suffix].id]
  description = "IDs of all public subnets, which hold the NAT gateways and the workbench"
}
output "private_subnet_a_id" {
  value       = aws_subnet.private[var.availability_zone_suffixes[0]].id
  description = "ID of the private subnet in the first zone"
}
output "private_subnet_b_id" {
  value       = aws_subnet.private[var.availability_zone_suffixes[1]].id
  description = "ID of the private subnet in the second zone"
}
output "private_subnet_ids" {
  value       = [for suffix in var.availability_zone_suffixes : aws_subnet.private[suffix].id]
  description = "IDs of all private subnets, which the container instance Auto Scaling group spans"
}
output "private_subnet_ids_by_zone" {
  value       = { for suffix in var.availability_zone_suffixes : suffix => aws_subnet.private[suffix].id }
  description = "Private subnet IDs keyed by zone letter. The keys come from a variable and are known at plan, so a caller can for_each over this while the IDs are still unknown (rules.md B-8)"
}
output "nat_gateway_public_ips" {
  value       = [for suffix in var.availability_zone_suffixes : aws_eip.nat[suffix].public_ip]
  description = "Addresses the container instances and their tasks appear as from outside, one per zone. Worth having when an outside service rate-limits by source address"
}
output "default_security_group_id" {
  value       = aws_vpc.vpc.default_security_group_id
  description = "ID of the security group AWS creates with the VPC, which the _monolithic template admitted to the container instances. Nothing here carries it; anything launched into this VPC without a security group of its own lands in it, which is the only way that rule admits anything"
}
