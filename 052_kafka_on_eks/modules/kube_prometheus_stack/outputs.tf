output "namespace" {
  value       = kubectl_manifest.namespace.name
  description = "Namespace of the release, where the dashboard sidecar looks for ConfigMaps and the Grafana Ingress is created"
}
output "release_name" {
  value       = helm_release.kube_prometheus_stack.name
  description = "Name of the Helm release"
}
output "grafana_service_name" {
  value       = "${helm_release.kube_prometheus_stack.name}-grafana"
  description = "Name of the Grafana Service, which the chart derives from the release name. Derived here rather than by the caller, because the naming convention belongs to the chart (rules.md B-5)"
}
output "grafana_service_port" {
  value       = 80
  description = "Port the Grafana Service listens on - the chart's grafana.service.port default, confirmed with helm template at 48.1.1"
}
output "grafana_container_port" {
  value       = 3000
  description = "Port the Grafana container listens on - the chart's service targetPort. An ALB with target-type ip sends traffic here rather than to the Service port, so this is the port the pod-side security group rule opens"
}
output "grafana_admin_secret_name" {
  value       = aws_secretsmanager_secret.grafana.name
  description = "Name of the Secrets Manager secret holding Grafana's admin password"
}
output "grafana_password_command" {
  value       = "aws secretsmanager get-secret-value --secret-id ${aws_secretsmanager_secret.grafana.name} --query SecretString --output text"
  description = "Reads Grafana's admin password. The user name is admin"
}
output "amp_workspace_id" {
  value       = one(aws_prometheus_workspace.amp[*].id)
  description = "ID of the Amazon Managed Prometheus workspace, or null when enable_amazon_prometheus is false"
}
output "amp_workspace_endpoint" {
  value       = local.amp_endpoint
  description = "Prometheus-compatible endpoint of the workspace, or null when enable_amazon_prometheus is false"
}
output "prometheus_pods_command" {
  value       = "kubectl -n ${kubectl_manifest.namespace.name} get pods,pvc"
  description = "The stack's pods and Prometheus's volume claim. A Prometheus pod Pending with its claim Pending points at the StorageClass or the EBS CSI driver"
}
