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
  description = "IDs of all public subnets"
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
  description = "IDs of all private subnets, which is where the container instances and the task ENIs are placed"
}
output "private_subnet_ids_by_zone" {
  value       = { for suffix in var.availability_zone_suffixes : suffix => aws_subnet.private[suffix].id }
  description = "Private subnet IDs keyed by zone letter. The keys come from a variable and are known at plan, so a caller can for_each over this while the IDs are still unknown (rules.md B-8)"
}
output "nat_gateway_public_ips" {
  value       = [for suffix in var.availability_zone_suffixes : aws_eip.nat[suffix].public_ip]
  description = "Addresses the tasks appear as from outside, one per zone. Worth having when an outside service rate-limits by source address"
}
