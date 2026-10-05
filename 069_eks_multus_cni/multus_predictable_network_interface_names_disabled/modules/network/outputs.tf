output "vpc_id" {
  value       = aws_vpc.vpc.id
  description = "ID of the VPC"
}
output "vpc_cidr_block" {
  value       = aws_vpc.vpc.cidr_block
  description = "CIDR block of the VPC"
}
output "public_subnet_a_id" {
  value       = aws_subnet.public_subnet_a.id
  description = "ID of public subnet A"
}
output "public_subnet_b_id" {
  value       = aws_subnet.public_subnet_b.id
  description = "ID of public subnet B"
}
output "private_subnet_a_id" {
  value       = aws_subnet.private_subnet_a.id
  description = "ID of private subnet A"
}
output "private_subnet_b_id" {
  value       = aws_subnet.private_subnet_b.id
  description = "ID of private subnet B"
}
output "public_subnet_ids" {
  value       = [aws_subnet.public_subnet_a.id, aws_subnet.public_subnet_b.id]
  description = "IDs of all public subnets"
}
output "private_subnet_ids" {
  value       = [aws_subnet.private_subnet_a.id, aws_subnet.private_subnet_b.id]
  description = "IDs of all private subnets"
}
output "availability_zones" {
  value       = [aws_subnet.public_subnet_a.availability_zone, aws_subnet.public_subnet_b.availability_zone]
  description = "Availability zones the subnets span, in a/b order"
}
output "public_subnet_a_cidr_block" {
  value       = aws_subnet.public_subnet_a.cidr_block
  description = "CIDR block of public subnet A"
}
output "public_subnet_b_cidr_block" {
  value       = aws_subnet.public_subnet_b.cidr_block
  description = "CIDR block of public subnet B"
}
output "private_subnet_a_cidr_block" {
  value       = aws_subnet.private_subnet_a.cidr_block
  description = "CIDR block of private subnet A. Exposed because the Multus network attachment carves its address range out of this block and the VPC CIDR reservations have to name the same sub-blocks, so both read one value rather than recomputing the module's own subnet arithmetic (rules.md B-5)"
}
output "private_subnet_b_cidr_block" {
  value       = aws_subnet.private_subnet_b.cidr_block
  description = "CIDR block of private subnet B"
}
output "multus_subnet_a_id" {
  value       = aws_subnet.multus_subnet_a.id
  description = "ID of the subnet the nodes attach their Multus ENIs in. A subnet of its own, so nothing else in the VPC draws addresses from the space the attachment hands to pods"
}
output "multus_subnet_a_cidr_block" {
  value       = aws_subnet.multus_subnet_a.cidr_block
  description = "CIDR of the Multus subnet. The attachment writes this into its host-local configuration, which is what decides the link route ipvlan installs on a pod's net1 - so it covers the Multus network only and leaves the node's subnet to the VPC CNI"
}
output "multus_pod_range_cidr" {
  value       = local.multus_pod_range_cidr
  description = "The block inside the Multus subnet that host-local hands to pods. Exposed because two things have to name exactly this block and must not derive it separately: the attachment's IPAM range and the caller's VPC subnet CIDR reservation, which has to exist before any node attaches an ENI in this subnet (rules.md B-5)"
}
