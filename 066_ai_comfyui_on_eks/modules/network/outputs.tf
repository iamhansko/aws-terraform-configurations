output "vpc_id" {
  value       = aws_vpc.vpc.id
  description = "ID of the VPC"
}
output "vpc_cidr_block" {
  value       = aws_vpc.vpc.cidr_block
  description = "CIDR block of the VPC, re-exposed so a caller writing a rule for in-VPC traffic reads the same value the subnets were derived from (rules.md B-5)"
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
output "private_subnet_cidr_blocks" {
  value       = [for suffix in var.availability_zone_suffixes : aws_subnet.private[suffix].cidr_block]
  description = "CIDR blocks of the private subnets, in zone order. The internal ALB sits in these, so they are also where traffic to the pods comes from - the ComfyUI NetworkPolicy admits exactly these (rules.md B-5)"
}
output "availability_zones" {
  value       = [for suffix in var.availability_zone_suffixes : "${var.region}${suffix}"]
  description = "The zones this network spans, which is also the ceiling on where Karpenter can place a GPU node"
}
output "subnet_cidr_blocks" {
  value = {
    public  = { for suffix, subnet in aws_subnet.public : suffix => subnet.cidr_block }
    private = { for suffix, subnet in aws_subnet.private : suffix => subnet.cidr_block }
  }
  description = "What the CIDR derivation produced, by tier and zone. Worth reading once after changing vpc_cidr_block or the subnet sizing"
}
output "nat_gateway_id" {
  value       = aws_nat_gateway.nat_gateway.id
  description = "ID of the regional NAT gateway"
}
output "nat_public_ips" {
  value       = { for suffix, eip in aws_eip.nat : suffix => eip.public_ip }
  description = "The addresses private subnets appear from, by zone - what HuggingFace and the container registries see the GPU nodes and builds as"
}
output "nat_zones_with_addresses" {
  value       = sort(var.nat_availability_zone_suffixes)
  description = "Zones the regional gateway has an address in. A private subnet in a zone not listed here still reaches the internet, over a cross-zone hop that is billed (rules.md B-5)"
}
output "s3_gateway_endpoint_id" {
  value       = var.create_s3_gateway_endpoint ? aws_vpc_endpoint.s3[0].id : null
  description = "ID of the S3 gateway endpoint, or null when create_s3_gateway_endpoint is false"
}
