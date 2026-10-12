output "release_name" {
  value       = helm_release.aws_load_balancer_controller.name
  description = "Name of the release"
}
output "namespace" {
  value       = var.namespace
  description = "Namespace the controller runs in, re-exposed so the caller's diagnostic commands read one value (rules.md B-5)"
}
output "cluster_name" {
  value       = var.cluster_name
  description = "The cluster name this controller was told, re-exposed so it can be compared against the cluster it is actually installed on. That mismatch is the _monolithic template's bug and it produces no error at all (rules.md B-5/G-3)"
}
output "role_arn" {
  value       = aws_iam_role.aws_load_balancer_controller.arn
  description = "ARN of the controller's IAM role. Reusable across clusters because Pod Identity puts nothing cluster-specific in the trust policy"
}
output "chart_version" {
  value       = var.chart_version
  description = "Version installed, pinned where the _monolithic template left it floating"
}
output "status_command" {
  value       = "kubectl -n ${var.namespace} get deployment ${var.release_name} -o wide"
  description = "Whether the controller is Available. A Service of type LoadBalancer that never gets an address usually means this is not Ready rather than anything about the Service"
}
output "log_command" {
  value       = "kubectl -n ${var.namespace} logs deploy/${var.release_name} --tail 100"
  description = "What the controller decided. An AccessDenied loop here means the Pod Identity association is not being used - check that the pod carries AWS_CONTAINER_CREDENTIALS_FULL_URI, which the pod identity agent injects and which is missing if that addon is not installed"
}
output "owned_load_balancer_command" {
  value       = "aws resourcegroupstaggingapi get-resources --tag-filters Key=elbv2.k8s.aws/cluster,Values=${var.cluster_name} --resource-type-filters elasticloadbalancing:loadbalancer --query 'ResourceTagMappingList[].ResourceARN' --output table"
  description = "Load balancers tagged for this cluster. Run it for both clusters: a load balancer showing up under the wrong cluster name is the _monolithic template's clusterName mix-up, and it is the only way that bug becomes visible (rules.md G-3)"
}
