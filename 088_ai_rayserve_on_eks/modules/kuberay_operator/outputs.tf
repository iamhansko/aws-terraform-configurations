output "release_name" {
  value       = helm_release.kuberay_operator.name
  description = "Name of the KubeRay operator Helm release"
}

output "release_status" {
  value       = helm_release.kuberay_operator.status
  description = "Status the provider last recorded for the release. A failed release stays in the cluster without being in state, and the next apply then reports \"cannot re-use a name that is still in use\" rather than the original cause (rules.md E-7)"
}

output "namespace" {
  value       = var.namespace
  description = "Namespace the operator runs in, re-exposed so callers do not restate it (rules.md B-5)"
}

output "chart_version" {
  value       = var.chart_version
  description = "Chart version installed, which also decides the RayService API version the cluster serves"
}

output "operator_status_command" {
  value       = "kubectl -n ${var.namespace} get deployment ${var.release_name}"
  description = "Command that shows the operator Deployment. A RayService that never produces a Ray cluster with no events on it usually means the operator is not running"
}

output "operator_log_command" {
  value       = "kubectl -n ${var.namespace} logs deploy/${var.release_name} --tail 100"
  description = "Command that reads the operator log, which is where a rejected RayService spec is explained"
}
