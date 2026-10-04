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
  description = "IDs of all private subnets, in zone order. The cluster and the node group both take this list - the control plane's interfaces belong where the nodes are, and with a private-only endpoint there is nothing for the public subnets to do on the cluster"
}
output "public_subnet_ids_by_zone" {
  value       = { for suffix, subnet in aws_subnet.public : suffix => subnet.id }
  description = "Public subnets keyed by zone suffix, for a caller that needs one specific zone - the workbench instance uses the first"
}
output "private_subnet_ids_by_zone" {
  value       = { for suffix, subnet in aws_subnet.private : suffix => subnet.id }
  description = "Private subnets keyed by zone suffix"
}
output "public_route_table_id" {
  value       = aws_route_table.public.id
  description = "ID of the public route table"
}
output "private_route_table_id" {
  value       = aws_route_table.private.id
  description = "ID of the private route table. One table for every private subnet, which is what a regional NAT gateway allows"
}
output "availability_zones" {
  value       = [for suffix in var.availability_zone_suffixes : "${var.region}${suffix}"]
  description = "The zones this network spans"
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
  description = "The addresses private subnets appear from, by zone. One per zone listed in nat_availability_zone_suffixes and no more"
}
output "public_subnet_tags" {
  value       = var.public_subnet_tags
  description = "Tags that actually landed on the public subnets, re-exposed from the input so a caller can read in terraform output what the load balancer controller will be matching on (rules.md B-5)"
}
