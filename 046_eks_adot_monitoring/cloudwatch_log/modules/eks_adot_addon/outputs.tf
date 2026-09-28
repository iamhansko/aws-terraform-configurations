output "adot_addon_arn" {
  value       = aws_eks_addon.adot.arn
  description = "ARN of the adot EKS add-on"
}
output "addon_version" {
  value       = aws_eks_addon.adot.addon_version
  description = "Version EKS actually installed. Worth reading when a configuration key is rejected: the schema is versioned with the add-on, and leaving addon_version null means this can change between applies"
}
output "configuration_values" {
  value       = aws_eks_addon.adot.configuration_values
  description = "The JSON the add-on was configured with. Read it when a pipeline produces no data: a key in the wrong place is valid JSON the add-on ignores, and nothing reports that (rules.md E-5)"
}
output "operator_namespace" {
  value       = var.operator_namespace
  description = "Namespace the operator and its collectors run in, re-exposed so the caller's diagnostic commands read one value (rules.md B-5)"
}
output "collector_role_arns" {
  value       = { for key, role in aws_iam_role.adot_collector_iam_role : key => role.arn }
  description = "IRSA role ARN per enabled collector, keyed by pipeline. One role each rather than one shared role, because a trust policy names exactly one service account and the three collectors need different AWS permissions"
}
output "otlp_endpoint" {
  value       = var.otlp_ingest == null ? null : "http://adot-col-otlp-ingest-collector.${var.operator_namespace}.svc.cluster.local:4317"
  description = "Where an instrumented application sends traces, or null when the OTLP ingest collector is not enabled. The Service name is the add-on's - the collector name with a -collector suffix - so it is derived here rather than restated by whatever workload has to be pointed at it (rules.md B-5)"
}
output "collector_status_command" {
  value       = "kubectl -n ${var.operator_namespace} get opentelemetrycollectors,deployments,daemonsets,pods"
  description = "What the add-on actually built. An OpenTelemetryCollector with no matching Deployment or DaemonSet means the operator has not reconciled it, which is usually its webhook failing to serve - check cert-manager first"
}
output "collector_log_command" {
  value       = "kubectl -n ${var.operator_namespace} logs -l app.kubernetes.io/component=opentelemetry-collector --tail 100 --all-containers"
  description = "Where an exporter's own failures appear. A rejected AssumeRoleWithWebIdentity or an AccessDenied from the destination shows up here and nowhere else - the collector stays Running either way"
}
output "operator_log_command" {
  value       = "kubectl -n ${var.operator_namespace} logs deploy/opentelemetry-operator-controller-manager --tail 100"
  description = "The operator's own account, for when a collector object exists and nothing was built from it"
}
