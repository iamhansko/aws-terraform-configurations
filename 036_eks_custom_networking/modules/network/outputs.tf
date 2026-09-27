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
output "pod_subnet_ids" {
  value       = var.secondary_cidr_block == null ? [] : [aws_subnet.pod_subnet_a[0].id, aws_subnet.pod_subnet_b[0].id]
  description = "IDs of the pod subnets in the secondary CIDR, or an empty list when no secondary CIDR was associated"
}
output "pod_subnets_by_az" {
  value = var.secondary_cidr_block == null ? {} : {
    "${data.aws_region.current.region}a" = aws_subnet.pod_subnet_a[0].id
    "${data.aws_region.current.region}b" = aws_subnet.pod_subnet_b[0].id
  }
  description = "Pod subnet IDs keyed by availability zone name, which is the shape an ENIConfig per zone needs. Keyed this way on purpose: the keys come from the region data source and are known at plan time, so a caller can drive for_each with them, whereas keying on aws_subnet.availability_zone would produce keys that are unknown until apply (rules.md B-8)"
}
