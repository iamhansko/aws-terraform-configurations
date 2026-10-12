output "vpc_id" {
  value       = aws_vpc.vpc.id
  description = "ID of the VPC"
}
output "vpc_cidr_block" {
  value       = aws_vpc.vpc.cidr_block
  description = "CIDR block of the VPC"
}
# Per-zone outputs for a caller that needs one specific zone, and the array form for a caller that wants all
# of them (rules.md C-3).
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
  description = "IDs of all public subnets, which hold the load balancer and the NAT instances"
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
  description = "IDs of all private subnets, which the GPU Auto Scaling group and the ECS task span"
}
output "nat_instance_ids" {
  value       = [for suffix in var.availability_zone_suffixes : aws_instance.nat[suffix].id]
  description = "IDs of the NAT instances, one per zone. Their console output is where a NAT that does not forward explains itself"
}
output "nat_public_ips" {
  value       = [for suffix in var.availability_zone_suffixes : aws_instance.nat[suffix].public_ip]
  description = "Addresses the GPU instance and the ComfyUI task appear as from outside, one per zone. A NAT instance has no Elastic IP, so these change when one is replaced"
}
output "flow_log_group_name" {
  value       = aws_cloudwatch_log_group.flow_log.name
  description = "Log group the VPC flow log writes to"
}
