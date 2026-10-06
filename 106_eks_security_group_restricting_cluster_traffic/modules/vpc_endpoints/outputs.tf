output "interface_endpoint_ids" {
  value       = { for k, e in aws_vpc_endpoint.interface : k => e.id }
  description = "IDs of the interface endpoints, keyed by short service name"
}
output "interface_services" {
  value       = var.interface_services
  description = "Short service names of the interface endpoints created, re-exposed so a caller can list what the cluster can actually reach without restating it (rules.md B-5)"
}
output "s3_gateway_endpoint_id" {
  value       = var.create_s3_gateway_endpoint ? aws_vpc_endpoint.s3[0].id : null
  description = "ID of the S3 gateway endpoint, or null when it was not created"
}
output "endpoint_check_command" {
  value       = "aws ec2 describe-vpc-endpoints --filters Name=vpc-id,Values=${var.vpc_id} --query 'VpcEndpoints[].[ServiceName,VpcEndpointType,State]' --output table"
  description = "Command listing every endpoint in the VPC and its state. The first thing to check when nodes fail to join or images fail to pull on a cluster with no NAT gateway: an endpoint in any state other than available means that API is unreachable from the private subnets"
}

output "security_group_id" {
  value       = aws_security_group.vpc_endpoint_security_group.id
  description = "ID of the security group in front of the interface endpoints. The caller needs it to write the cluster's egress rule toward these endpoints, which is the rule this project is about"
}

output "s3_prefix_list_id" {
  value       = var.create_s3_gateway_endpoint ? aws_vpc_endpoint.s3[0].prefix_list_id : null
  description = <<-DESC
    Prefix list ID of the S3 gateway endpoint, for a security group rule whose destination is S3.

    The gateway endpoint resource exposes this directly, which is what makes the _monolithic
    template's whole Lambda unnecessary: it packaged a Python function, gave it an IAM role and
    ec2:DescribeManagedPrefixLists, and invoked it through aws_lambda_invocation purely to look this
    value up by name. Five resources replaced by one attribute (rules.md E-2 is the same argument for
    Kubernetes objects - use what the provider already models).
  DESC
}
