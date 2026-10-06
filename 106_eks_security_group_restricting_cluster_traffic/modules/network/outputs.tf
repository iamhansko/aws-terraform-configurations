output "vpc_id" {
  value       = aws_vpc.vpc.id
  description = "ID of the VPC"
}
output "vpc_cidr_block" {
  value       = aws_vpc.vpc.cidr_block
  description = "CIDR block of the VPC, re-exposed so a caller adding a security group rule for in-VPC traffic reads the same value the subnets were derived from (rules.md B-5)"
}
output "public_subnet_ids" {
  value       = [for suffix in var.availability_zone_suffixes : aws_subnet.public[suffix].id]
  description = "IDs of all public subnets, in zone order. The array form for callers that need every subnet, alongside the per-zone map below (rules.md C-3)"
}
output "private_subnet_ids" {
  value       = [for suffix in var.availability_zone_suffixes : aws_subnet.private[suffix].id]
  description = "IDs of all private subnets, in zone order"
}
output "public_subnet_ids_by_zone" {
  value       = { for suffix, subnet in aws_subnet.public : suffix => subnet.id }
  description = "Public subnets keyed by zone suffix, for a caller that needs one specific zone - the workbench instance uses the first"
}
output "private_subnet_ids_by_zone" {
  value       = { for suffix, subnet in aws_subnet.private : suffix => subnet.id }
  description = "Private subnets keyed by zone suffix"
}
output "availability_zones" {
  value       = [for suffix in var.availability_zone_suffixes : "${var.region}${suffix}"]
  description = "The zones this network spans. The script on the workbench builds its clusters across what the VPC offers, so this is the ceiling on how far they spread"
}
output "subnet_cidr_blocks" {
  value = {
    public  = { for suffix, subnet in aws_subnet.public : suffix => subnet.cidr_block }
    private = { for suffix, subnet in aws_subnet.private : suffix => subnet.cidr_block }
  }
  description = "What the CIDR derivation produced. Worth reading once after changing vpc_cidr_block: the _monolithic template listed these literally, so a different VPC block silently left them outside it"
}
output "nat_gateway_id" {
  value       = aws_nat_gateway.nat_gateway.id
  description = "ID of the regional NAT gateway"
}
output "nat_public_ips" {
  value       = { for suffix, eip in aws_eip.nat : suffix => eip.public_ip }
  description = "The addresses private subnets appear from, by zone. One per zone listed in nat_availability_zone_suffixes and no more - the _monolithic template allocated a third and attached it to nothing (rules.md A-5)"
}
output "nat_zones_with_addresses" {
  value       = sort(var.nat_availability_zone_suffixes)
  description = "Zones the regional gateway has an address in. A private subnet in a zone not listed here still reaches the internet, over a cross-zone hop that is billed - re-exposed because that cost is invisible otherwise (rules.md B-5)"
}

# One route table per tier rather than one per zone, because the NAT gateway is
# regional - a zonal gateway would need a table per zone to route to the right one.
#
# Exposed because a gateway VPC endpoint attaches to route tables rather than to
# subnets, so the caller that creates one needs these IDs and has no other way to
# reach them (rules.md C-3 is the same argument about subnet outputs).
output "public_route_table_id" {
  value       = aws_route_table.public.id
  description = "ID of the public route table, for a gateway VPC endpoint that has to add its prefix list route here"
}

output "private_route_table_id" {
  value       = aws_route_table.private.id
  description = "ID of the private route table, for a gateway VPC endpoint that has to add its prefix list route here"
}

output "route_table_ids" {
  value       = [aws_route_table.public.id, aws_route_table.private.id]
  description = "Both route tables, for a caller that wants a gateway endpoint reachable from either tier"
}
