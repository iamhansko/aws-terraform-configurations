output "name" {
  value       = var.name
  description = "Name of the Application object, re-exposed so the verification commands and the caller read one value (rules.md B-5)"
}

output "argocd_namespace" {
  value       = var.argocd_namespace
  description = "Namespace the Application object lives in, which is where Argo CD runs"
}

output "destination_namespace" {
  value       = var.destination_namespace
  description = "Namespace Argo CD deploys the synced objects into"
}

output "application_status_command" {
  value       = "kubectl -n ${var.argocd_namespace} get application ${var.name} -o jsonpath='sync={.status.sync.status} health={.status.health.status}{\"\\n\"}'"
  description = "Synced and Healthy is the end state. OutOfSync with no progress means Argo CD cannot reach the repository; Unknown health usually means it has not been permitted to read the objects it created"
}

output "application_conditions_command" {
  value       = "kubectl -n ${var.argocd_namespace} get application ${var.name} -o jsonpath='{range .status.conditions[*]}{.type}: {.message}{\"\\n\"}{end}'"
  description = "Where a sync failure explains itself. A forbidden message here is the capability role's cluster access policy rather than anything about the repository"
}

output "deployed_objects_command" {
  value       = "kubectl -n ${var.destination_namespace} get all"
  description = "What Argo CD actually created. None of it is declared in this configuration - it came from the repository"
}
