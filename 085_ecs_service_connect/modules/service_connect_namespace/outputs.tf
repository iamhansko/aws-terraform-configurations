output "arn" {
  value       = aws_service_discovery_http_namespace.service_connect_namespace.arn
  description = "ARN of the namespace, which is what the cluster default and a service_connect_configuration take"
}
output "id" {
  value       = aws_service_discovery_http_namespace.service_connect_namespace.id
  description = "ID of the namespace"
}
output "name" {
  value       = aws_service_discovery_http_namespace.service_connect_namespace.name
  description = "Name of the namespace"
}
output "list_services_command" {
  value       = "aws servicediscovery list-services --filters Name=NAMESPACE_ID,Values=${aws_service_discovery_http_namespace.service_connect_namespace.id},Condition=EQ --query 'Services[].[Name,Id,InstanceCount]' --output table"
  description = "The Cloud Map services ECS created in the namespace, one per Service Connect endpoint. Empty after the server service exists means its service_connect_configuration published nothing"
}
output "discover_instances_command_prefix" {
  value       = "aws servicediscovery discover-instances --namespace-name ${aws_service_discovery_http_namespace.service_connect_namespace.name} --query 'Instances[].[InstanceId,HealthStatus,Attributes.AWS_INSTANCE_IPV4]' --output table --service-name"
  description = "discover-instances against this namespace, ending in --service-name so the caller appends the discovery name it published - the tasks ECS registered behind that endpoint"
}
