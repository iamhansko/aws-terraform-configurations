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
output "public_subnet_c_id" {
  value       = aws_subnet.public_subnet_c.id
  description = "ID of public subnet C"
}
output "private_subnet_a_id" {
  value       = aws_subnet.private_subnet_a.id
  description = "ID of private subnet A"
}
output "private_subnet_b_id" {
  value       = aws_subnet.private_subnet_b.id
  description = "ID of private subnet B"
}
output "private_subnet_c_id" {
  value       = aws_subnet.private_subnet_c.id
  description = "ID of private subnet C"
}
output "public_subnet_ids" {
  value       = [aws_subnet.public_subnet_a.id, aws_subnet.public_subnet_b.id, aws_subnet.public_subnet_c.id]
  description = "IDs of all public subnets. Exposed alongside the per-zone outputs so a caller that needs every subnet does not rebuild the list (rules.md C-3)"
}
output "private_subnet_ids" {
  value       = [aws_subnet.private_subnet_a.id, aws_subnet.private_subnet_b.id, aws_subnet.private_subnet_c.id]
  description = "IDs of all private subnets. This is the list the node group spans, and therefore the set of zones the autoscaler can launch nodes into"
}
output "availability_zones" {
  value       = [aws_subnet.public_subnet_a.availability_zone, aws_subnet.public_subnet_b.availability_zone, aws_subnet.public_subnet_c.availability_zone]
  description = "Availability zones the subnets span, in a/b/c order. Re-exposed because the demo's zone spread constraint balances across exactly these, so a caller describing it reads the real list rather than assuming three (rules.md B-5)"
}
