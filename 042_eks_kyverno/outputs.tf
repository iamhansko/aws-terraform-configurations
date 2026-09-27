# Every output is a projection of local.outputs in main.tf, which is also what the
# README written onto the VS Code instance is rendered from (rules.md H-2). No value
# expression is written here: an output that built its own value would be missing
# from that README, and nothing would fail to say so - the apply would succeed
# either way. Whether the pattern still holds is checked by counting: the number of
# output blocks here must equal the number of entries in local.outputs.
#
# description is the one thing repeated, because Terraform rejects an expression
# there ("Variables not allowed") - it has to be a literal.
output "vscode_url" {
  value       = local.outputs.vscode_url.value
  description = "URL to access the code-server web UI on the VS Code EC2 instance"
}
output "cluster_name" {
  value       = local.outputs.cluster_name.value
  description = "Name of the EKS cluster"
}
output "cluster_endpoint" {
  value       = local.outputs.cluster_endpoint.value
  description = "API server endpoint of the EKS cluster"
}
output "pod_security_standard" {
  value       = local.outputs.pod_security_standard.value
  description = "Which Pod Security Standard profile the installed Kyverno policies check against"
}
output "validation_failure_action" {
  value       = local.outputs.validation_failure_action.value
  description = "Whether a policy violation is recorded (Audit) or the pod is rejected (Enforce)"
}
output "grafana_url" {
  value       = local.outputs.grafana_url.value
  description = "URL of the pre-created load balancer fronting Grafana"
}
output "grafana_admin_user" {
  value       = local.outputs.grafana_admin_user.value
  description = "Grafana admin username. The password is deliberately not an output: it is supplied as a sensitive variable and is not written into the instance README (rules.md H-2)"
}
output "policies_check_command" {
  value       = local.outputs.policies_check_command.value
  description = "Command listing the ClusterPolicy objects the kyverno-policies chart installed"
}
output "policy_report_command" {
  value       = local.outputs.policy_report_command.value
  description = "Command listing the PolicyReports Kyverno produced per namespace"
}
output "prometheus_check_command" {
  value       = local.outputs.prometheus_check_command.value
  description = "Command listing the Prometheus pods that feed the Grafana dashboards"
}
output "grafana_datasource_check_command" {
  value       = local.outputs.grafana_datasource_check_command.value
  description = "Command showing whether the operator attached the datasource to the Grafana instance"
}
output "grafana_ingress_check_command" {
  value       = local.outputs.grafana_ingress_check_command.value
  description = "Command showing the Ingress the Grafana operator created and the address it got"
}
output "adopted_load_balancer_check_command" {
  value       = local.outputs.adopted_load_balancer_check_command.value
  description = "Command listing every load balancer tagged for this cluster. One is correct; two means adoption failed and the controller built its own (rules.md G-3)"
}
output "update_kubeconfig_command" {
  value       = local.outputs.update_kubeconfig_command.value
  description = "Command that points kubectl on the VS Code instance at the cluster"
}
