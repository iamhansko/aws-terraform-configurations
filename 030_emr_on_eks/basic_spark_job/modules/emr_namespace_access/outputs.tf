output "namespace" {
  value       = var.namespace
  description = "Namespace EMR on EKS is authorised in, re-exposed so the virtual cluster does not restate it (rules.md B-5)"
}

output "emr_user_name" {
  value       = var.emr_user_name
  description = "Kubernetes user the service-linked role is mapped to"
}

output "service_linked_role_arn" {
  value       = local.emr_service_linked_role_arn
  description = "The path-stripped ARN written into aws-auth. Worth exposing: it is not the role's real ARN, and the difference is the thing most likely to be edited back to something that does not work (rules.md E-6)"
}

output "aws_auth_check_command" {
  value       = "kubectl -n kube-system get configmap aws-auth -o jsonpath='{.data.mapRoles}' ; echo"
  description = "Command that prints the aws-auth mappings. The EMR entry and the node instance role entry both have to be here - if the node entry is gone, something replaced the ConfigMap instead of merging into it, and the nodes have left the cluster"
}

output "rbac_check_command" {
  value       = "kubectl -n ${var.namespace} get role,rolebinding"
  description = "Command that shows the Role and RoleBinding in the namespace. Both missing is why CreateVirtualCluster reports \"Unauthorized to perform read namespace\""
}

output "access_check_command" {
  value       = "kubectl auth can-i get namespace --namespace ${var.namespace} --as ${var.emr_user_name}"
  description = "Command that asks the API server directly whether the mapped user may read the namespace. This is the exact permission EMR on EKS checks when creating a virtual cluster, so a \"no\" here is the failure before it happens"
}
