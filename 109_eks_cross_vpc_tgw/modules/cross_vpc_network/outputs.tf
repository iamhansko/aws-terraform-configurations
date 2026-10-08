output "vpc_id" {
  value       = aws_vpc.vpc.id
  description = "ID of the VPC"
}

output "vpc_cidr_block" {
  value       = aws_vpc.vpc.cidr_block
  description = "Primary CIDR block, which is what the other VPC routes to across the transit gateway"
}

output "secondary_cidr_block" {
  value       = aws_vpc_ipv4_cidr_block_association.secondary.cidr_block
  description = "Non-routable CIDR the cluster and node tiers come out of"
}

output "public_subnet_ids" {
  value       = [for subnet in aws_subnet.public : subnet.id]
  description = "Public subnets, for the ALB and the workbench"
}

output "private_subnet_ids" {
  value       = [for subnet in aws_subnet.private : subnet.id]
  description = "Private subnets, which hold the private NAT gateways and the transit gateway attachment"
}

output "cluster_subnet_ids" {
  value       = [for subnet in aws_subnet.cluster : subnet.id]
  description = "Cluster subnets, for the EKS control plane's cross-account ENIs"
}

output "node_subnet_ids" {
  value       = [for subnet in aws_subnet.node : subnet.id]
  description = "Node subnets, for the node group and every pod address"
}

output "public_subnet_ids_by_zone" {
  value       = { for suffix, subnet in aws_subnet.public : suffix => subnet.id }
  description = "Public subnets keyed by zone suffix, for a caller that needs one specific zone - the workbench uses the first"
}

output "private_subnet_ids_by_zone" {
  value       = { for suffix, subnet in aws_subnet.private : suffix => subnet.id }
  description = "Private subnets keyed by zone suffix"
}

output "node_subnet_ids_by_zone" {
  value       = { for suffix, subnet in aws_subnet.node : suffix => subnet.id }
  description = "Node subnets keyed by zone suffix"
}

output "availability_zones" {
  value       = [for suffix in var.availability_zone_suffixes : "${var.region}${suffix}"]
  description = "Full availability zone names this VPC spans"
}

output "public_nat_gateway_ids" {
  value       = { for suffix, gateway in aws_nat_gateway.public : suffix => gateway.id }
  description = "Public NAT gateways by zone, which give the private and node tiers outbound internet"
}

output "private_nat_gateway_ids" {
  value       = { for suffix, gateway in aws_nat_gateway.private : suffix => gateway.id }
  description = "Private NAT gateways by zone. These are the piece that makes a non-routable pod address usable across the transit gateway: they translate it into an address in the routable private subnet they sit in"
}

output "private_nat_gateway_addresses" {
  value       = { for suffix, gateway in aws_nat_gateway.private : suffix => gateway.private_ip }
  description = "The addresses traffic from this VPC's nodes appears to come from on the other side. Worth having: a packet capture or a security group rule on the far side sees these, not the pod's own address"
}

output "route_tables_command" {
  value       = "aws ec2 describe-route-tables --filters Name=vpc-id,Values=${aws_vpc.vpc.id} --query 'RouteTables[].[Tags[?Key==`Name`].Value|[0],Routes[].[DestinationCidrBlock,NatGatewayId,TransitGatewayId,GatewayId]]' --output json"
  description = "Command that prints every route table in this VPC with its routes. This is where the design is visible: the node tier reaches the peer through a NAT gateway, the private tier reaches it through the transit gateway"
}
