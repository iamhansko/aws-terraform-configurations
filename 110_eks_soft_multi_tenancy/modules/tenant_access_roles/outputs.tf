output "role_arns" {
  value       = { for label, role in aws_iam_role.tenant : label => role.arn }
  description = "Each tenant's role ARN, by tenant label. These are what a demo assumes to act as one tenant or the other"
}
output "role_names" {
  value       = { for label, role in aws_iam_role.tenant : label => role.name }
  description = "Each tenant's role name"
}
output "namespaces" {
  value       = var.tenants
  description = "Which namespace each tenant's role may edit, re-exposed so it can be compared against the namespaces the workload module actually creates - a role scoped to a namespace that does not exist grants nothing and reports nothing (rules.md B-5)"
}
output "kubernetes_user_names" {
  value       = { for label, entry in aws_eks_access_entry.tenant : label => entry.user_name }
  description = "The Kubernetes username each role maps to. This is what appears in an audit log and in an RBAC denial, which is why it is named after the tenant rather than left generated"
}
output "access_policy_arn" {
  value       = var.access_policy_arn
  description = "The policy each tenant is granted within its namespace. Edit rather than Admin, and namespace-scoped rather than cluster-scoped - which together are what make this soft multi-tenancy"
}
output "assume_role_commands" {
  value = {
    for label, role in aws_iam_role.tenant : label =>
    "aws sts assume-role --role-arn ${role.arn} --role-session-name ${label}-demo --query Credentials --output json"
  }
  description = "How to become each tenant. Export the returned credentials and run kubectl: the same cluster then answers for one namespace and refuses the other, which is the demonstration"
}
output "list_access_entries_command" {
  value       = "aws eks list-access-entries --cluster-name ${var.cluster_name} --query 'accessEntries' --output table"
  description = "Every principal the cluster knows. A tenant role missing here explains a kubectl that fails to authenticate rather than one that is denied - the two look different and are diagnosed differently"
}
output "describe_access_scope_commands" {
  value = {
    for label, role in aws_iam_role.tenant : label =>
    "aws eks list-associated-access-policies --cluster-name ${var.cluster_name} --principal-arn ${role.arn} --query 'associatedAccessPolicies[].[policyArn,accessScope.type,accessScope.namespaces]' --output json"
  }
  description = "What each tenant is actually allowed, read from the cluster. An accessScope type of cluster here rather than namespace means the isolation is not in place, and nothing else would show it"
}
