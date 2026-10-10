output "namespace_id" {
  value       = aws_service_discovery_private_dns_namespace.service_discovery_namespace.id
  description = "ID of the private DNS namespace"
}
output "namespace_name" {
  value       = aws_service_discovery_private_dns_namespace.service_discovery_namespace.name
  description = "DNS name of the namespace"
}
output "hosted_zone_id" {
  value       = aws_service_discovery_private_dns_namespace.service_discovery_namespace.hosted_zone
  description = "Route 53 private hosted zone Cloud Map created for the namespace"
}
output "service_arn" {
  value       = aws_service_discovery_service.service_discovery_service.arn
  description = "ARN of the Cloud Map service, which is what an ECS service registry takes"
}
output "service_id" {
  value       = aws_service_discovery_service.service_discovery_service.id
  description = "ID of the Cloud Map service"
}
output "fqdn" {
  value       = "${aws_service_discovery_service.service_discovery_service.name}.${aws_service_discovery_private_dns_namespace.service_discovery_namespace.name}"
  description = "Name the registered tasks are resolvable at from inside the VPC, built from the two names rather than restated by the caller (rules.md B-5)"
}
output "list_instances_command" {
  value       = "aws servicediscovery list-instances --service-id ${aws_service_discovery_service.service_discovery_service.id} --query 'Instances[].[Id,Attributes.AWS_INSTANCE_IPV4]' --output table"
  description = "The tasks ECS registered in the service, one per running task with its ENI address"
}
output "hosted_zone_records_command" {
  value       = "aws route53 list-resource-record-sets --hosted-zone-id ${aws_service_discovery_private_dns_namespace.service_discovery_namespace.hosted_zone} --query \"ResourceRecordSets[?Type=='A'].[Name,ResourceRecords[0].Value,TTL]\" --output table"
  description = "The A records Cloud Map wrote into the private hosted zone - what a resolver in the VPC answers with"
}
