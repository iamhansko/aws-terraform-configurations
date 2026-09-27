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
output "storage_class_name" {
  value       = local.outputs.storage_class_name.value
  description = "Name of the default StorageClass backed by the EBS CSI driver"
}
output "grafana_url" {
  value       = local.outputs.grafana_url.value
  description = "URL of the pre-created load balancer fronting Grafana"
}
output "prometheus_url" {
  value       = local.outputs.prometheus_url.value
  description = "URL of the pre-created load balancer fronting Prometheus"
}
output "alertmanager_url" {
  value       = local.outputs.alertmanager_url.value
  description = "URL of the pre-created load balancer fronting Alertmanager"
}
output "grafana_admin_user" {
  value       = local.outputs.grafana_admin_user.value
  description = "Grafana admin username"
}
output "grafana_password_command" {
  value       = local.outputs.grafana_password_command.value
  description = "Command reading the Grafana admin password out of the cluster. A command rather than the value, so the password is not written into the instance README that an unauthenticated code-server serves (rules.md H-2)"
}
output "ingress_check_command" {
  value       = local.outputs.ingress_check_command.value
  description = "Command listing the three monitoring Ingresses and the address each one got"
}
output "adopted_load_balancer_check_command" {
  value       = local.outputs.adopted_load_balancer_check_command.value
  description = "Command listing every load balancer tagged for this cluster. Three is correct; six means adoption failed and the controller built its own (rules.md G-3)"
}
output "update_kubeconfig_command" {
  value       = local.outputs.update_kubeconfig_command.value
  description = "Command that points kubectl on the VS Code instance at the cluster"
}
