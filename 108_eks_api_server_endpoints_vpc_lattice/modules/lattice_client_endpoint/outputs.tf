output "endpoint_id" {
  value       = aws_vpc_endpoint.service_network.id
  description = "ID of the service network endpoint in the client VPC"
}
output "endpoint_security_group_id" {
  value       = aws_security_group.endpoint.id
  description = "The endpoint's security group. Anything allowed to reach it on 443 can reach the cluster's API server, which is why the extra CIDR list is empty by default"
}
output "endpoint_dns_name" {
  value       = var.create_private_hosted_zone ? data.aws_vpc_endpoint_associations.service_network[0].associations[0].dns_entry[0].dns_name : null
  description = "The name the endpoint publishes, read from the association rather than fetched by a Lambda with EC2 admin. Targeting it directly with kubectl fails TLS verification, because the API server's certificate names the cluster's hostname - which is what the private hosted zone is for"
}
output "private_hosted_zone_id" {
  value       = var.create_private_hosted_zone ? aws_route53_zone.api_server[0].zone_id : null
  description = "The private zone that makes the cluster's real hostname resolve inside the client VPC, or null when it was not created"
}
output "api_server_hostname" {
  value       = var.api_server_hostname
  description = "The hostname a client resolves, re-exposed so it can be compared against what the cluster's endpoint actually is (rules.md B-5)"
}
output "private_dns_created" {
  value       = var.create_private_hosted_zone
  description = "Whether the private zone exists. False leaves a working endpoint that kubectl cannot use, because the name it would have to target does not match the API server's certificate - re-exposed because that failure reads as a TLS problem rather than a DNS one (rules.md B-5)"
}
output "resolve_command" {
  value       = "dig +short ${var.api_server_hostname}"
  description = "Run this on a client in the client VPC. It should return a private address in that VPC - the endpoint's - rather than the cluster VPC's endpoint address or nothing at all. A NXDOMAIN here means the private hosted zone is missing or not associated with this VPC"
}
output "associations_command" {
  value       = "aws ec2 describe-vpc-endpoint-associations --vpc-endpoint-ids ${aws_vpc_endpoint.service_network.id} --query 'VpcEndpointAssociations[].[ServiceNetworkName,AssociatedResourceArn,DnsEntry.DnsName]' --output table"
  description = "What the endpoint is actually associated with, and the DNS name it publishes. This is the call the deleted Lambda made - kept as a command because it is the right thing to look at when the alias record points somewhere unexpected"
}
output "endpoint_state_command" {
  value       = "aws ec2 describe-vpc-endpoints --vpc-endpoint-ids ${aws_vpc_endpoint.service_network.id} --query 'VpcEndpoints[].[State,VpcEndpointType,ServiceNetworkArn]' --output table"
  description = "Whether the endpoint came up. A state other than available with the Lattice side ACTIVE usually means the subnets or the security group were rejected"
}
