output "propagation_policy_name" {
  value       = var.propagation_policy_name
  description = "Name of the PropagationPolicy, re-exposed so the commands that inspect it name the object that was created (rules.md B-5)"
}
output "deployment_name" {
  value       = var.deployment_name
  description = "Name of the Deployment on the Karmada API server"
}
output "member_cluster_names" {
  value       = var.member_cluster_names
  description = "Clusters the replicas were divided between, re-exposed so a policy targeting clusters that do not exist is visible in terraform output rather than only as a Deployment reporting no replicas"
}
output "expected_replicas_per_cluster" {
  value       = format("%d replicas across %d clusters at equal weight", var.replicas, length(var.member_cluster_names))
  description = "What the policy asks for, as a sentence. Worth having written down because it is the number to compare the member clusters' pod counts against - Karmada reports the aggregate on its own side, so an uneven split only shows up by looking in the members"
}
output "aggregate_check_command" {
  value       = "kubectl -n ${var.namespace} get deployment ${var.deployment_name} -o wide"
  description = "The Deployment as the Karmada API server sees it. The replica counts here are collected from the member clusters by Karmada; the pods themselves do not exist on this API server at all"
}
output "binding_check_command" {
  value       = "kubectl -n ${var.namespace} get resourcebinding ${var.deployment_name}-deployment -o jsonpath='{range .spec.clusters[*]}{.name}{\"=\"}{.replicas}{\"  \"}{end}{\"\\n\"}'"
  description = "The scheduler's actual decision: which cluster got how many replicas. This is the object to read when the split is not what the weights asked for, and it is also where a policy that matched nothing shows up - no ResourceBinding means the Deployment was never governed by any policy"
}
output "policy_check_command" {
  value       = "kubectl -n ${var.namespace} get propagationpolicy ${var.propagation_policy_name} -o yaml"
  description = "The policy itself. Its finalizer is karmada.io/propagation-policy-controller, which is why this object is applied with wait = true - see main.tf"
}
