output "interface_endpoint_ids" {
  value       = { for k, e in aws_vpc_endpoint.interface : k => e.id }
  description = "IDs of the interface endpoints, keyed by short service name"
}
output "interface_services" {
  value       = var.interface_services
  description = "Short service names of the interface endpoints created, re-exposed so a caller can list what reaches its API privately without restating it (rules.md B-5)"
}
output "s3_gateway_endpoint_id" {
  value       = var.create_s3_gateway_endpoint ? aws_vpc_endpoint.s3[0].id : null
  description = "ID of the S3 gateway endpoint, or null when it was not created"
}
output "endpoint_check_command" {
  value       = "aws ec2 describe-vpc-endpoints --filters Name=vpc-id,Values=${var.vpc_id} --query 'VpcEndpoints[].[ServiceName,VpcEndpointType,State]' --output table"
  description = "Command listing every endpoint in the VPC and its state. An endpoint in any state other than available is the first suspect when calls to that service from the private subnets time out"
}
output "security_group_id" {
  value       = aws_security_group.vpc_endpoint_security_group.id
  description = "ID of the security group in front of the interface endpoints"
}
