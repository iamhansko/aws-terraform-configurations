output "vpc_id" {
  value       = aws_vpc.vpc.id
  description = "ID of the client VPC"
}
output "vpc_cidr_block" {
  value       = aws_vpc.vpc.cidr_block
  description = "CIDR block of the client VPC, re-exposed so the endpoint's security group rule reads the same value the subnets were derived from (rules.md B-5)"
}
output "public_subnet_ids" {
  value       = [for suffix in var.availability_zone_suffixes : aws_subnet.public[suffix].id]
  description = "IDs of all subnets, in zone order. Both the workbench and the Lattice endpoint go here"
}
output "public_subnet_ids_by_zone" {
  value       = { for suffix, subnet in aws_subnet.public : suffix => subnet.id }
  description = "Subnets keyed by zone suffix, for a caller that needs one specific zone"
}
output "availability_zones" {
  value       = [for suffix in var.availability_zone_suffixes : "${var.region}${suffix}"]
  description = "The zones this VPC spans"
}
output "subnet_cidr_blocks" {
  value       = { for suffix, subnet in aws_subnet.public : suffix => subnet.cidr_block }
  description = "What the CIDR derivation produced. The _monolithic template listed these literally in a mapping, so a different VPC block left them outside the VPC"
}
