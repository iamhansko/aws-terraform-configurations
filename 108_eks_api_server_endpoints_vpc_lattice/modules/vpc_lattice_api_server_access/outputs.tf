output "service_network_arn" {
  value       = aws_vpclattice_service_network.service_network.arn
  description = "ARN of the service network, which the client VPC's endpoint attaches to (rules.md B-5)"
}
output "service_network_id" {
  value       = aws_vpclattice_service_network.service_network.id
  description = "ID of the service network"
}
output "service_network_name" {
  value       = aws_vpclattice_service_network.service_network.name
  description = "Name of the service network"
}
output "resource_gateway_id" {
  value       = aws_vpclattice_resource_gateway.gateway.id
  description = "ID of the resource gateway"
}
output "resource_gateway_security_group_id" {
  value       = aws_security_group.resource_gateway.id
  description = "The gateway's security group. Re-exposed because the rule letting it reach the API server is the one thing that turns a working Lattice configuration into a working connection, and its absence looks like a Lattice fault (rules.md B-5)"
}
output "resource_configuration_id" {
  value       = aws_vpclattice_resource_configuration.api_server.id
  description = "ID of the resource configuration"
}
output "resource_configuration_arn" {
  value       = aws_vpclattice_resource_configuration.api_server.arn
  description = "ARN of the resource configuration, which is what a cross-account version of this pattern would share through RAM"
}
output "api_server_hostname" {
  value       = var.api_server_hostname
  description = "The hostname clients resolve, re-exposed so the private hosted zone and the alias record read the same value the resource configuration was given - the _monolithic template split it out of the cluster endpoint four separate times (rules.md B-5)"
}
output "association_id" {
  value       = aws_vpclattice_service_network_resource_association.api_server.id
  description = "ID of the association. It has to exist before the client endpoint has anything to resolve, which is why the caller orders the endpoint module after this one"
}
output "port_ranges" {
  value       = var.port_ranges
  description = "What a client can reach through this configuration. The _monolithic template opened 1-65535 on a resource that serves one port"
}
output "describe_command" {
  value       = "aws vpc-lattice get-resource-configuration --resource-configuration-identifier ${aws_vpclattice_resource_configuration.api_server.id} --query '[status,type,protocol,portRanges,customDomainName,allowAssociationToShareableServiceNetwork]' --output json"
  description = "The configuration and its status. ACTIVE here with a client that still cannot connect points at the security group rules rather than at Lattice"
}
output "association_status_command" {
  value       = "aws vpc-lattice list-service-network-resource-associations --service-network-identifier ${aws_vpclattice_service_network.service_network.id} --query 'items[].[id,status,resourceConfigurationName]' --output table"
  description = "Whether the configuration is attached to the service network. A status other than ACTIVE means the client endpoint has nothing to resolve, however healthy the endpoint itself looks"
}
