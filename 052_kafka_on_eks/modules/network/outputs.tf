output "vpc_id" {
  value       = aws_vpc.vpc.id
  description = "ID of the VPC"
}
output "vpc_cidr_block" {
  value       = aws_vpc.vpc.cidr_block
  description = "Primary CIDR block of the VPC"
}
output "secondary_cidr_block" {
  value       = aws_vpc_ipv4_cidr_block_association.secondary.cidr_block
  description = "Secondary CIDR block the data plane subnets are carved from"
}
# Individual outputs for a caller that needs one specific subnet, list outputs for one that needs a
# whole tier (rules.md C-3).
output "public_subnet_a_id" {
  value       = aws_subnet.public_subnet_a.id
  description = "ID of public subnet A, where the workbench instance and the NAT gateway sit"
}
output "public_subnet_b_id" {
  value       = aws_subnet.public_subnet_b.id
  description = "ID of public subnet B"
}
output "private_subnet_a_id" {
  value       = aws_subnet.private_subnet_a.id
  description = "ID of RFC 1918 private subnet A"
}
output "private_subnet_b_id" {
  value       = aws_subnet.private_subnet_b.id
  description = "ID of RFC 1918 private subnet B"
}
output "data_plane_subnet_a_id" {
  value       = aws_subnet.data_plane_subnet_a.id
  description = "ID of data plane subnet A, in the secondary CIDR"
}
output "data_plane_subnet_b_id" {
  value       = aws_subnet.data_plane_subnet_b.id
  description = "ID of data plane subnet B, in the secondary CIDR"
}
output "public_subnet_ids" {
  value       = [aws_subnet.public_subnet_a.id, aws_subnet.public_subnet_b.id]
  description = "IDs of both public subnets"
}
output "private_subnet_ids" {
  value       = [aws_subnet.private_subnet_a.id, aws_subnet.private_subnet_b.id]
  description = "IDs of both RFC 1918 private subnets"
}
output "data_plane_subnet_ids" {
  value       = [aws_subnet.data_plane_subnet_a.id, aws_subnet.data_plane_subnet_b.id]
  description = "IDs of both data plane subnets - the EKS cluster, the managed node group and every Karpenter pool are placed here"
}
output "availability_zones" {
  value       = [aws_subnet.public_subnet_a.availability_zone, aws_subnet.public_subnet_b.availability_zone]
  description = "Availability zones the subnets span, in a/b order"
}
output "nat_gateway_public_ip" {
  value       = aws_eip.nat_gateway.public_ip
  description = "Address every node and pod reaches the internet from"
}
