output "name" {
  value       = var.name
  description = "Name of the instance object, re-exposed so the verification commands and the caller read one value (rules.md B-5)"
}

output "namespace" {
  value       = var.namespace
  description = "Namespace the instance and the objects kro built from it live in"
}

output "workload_name" {
  value       = var.workload_name
  description = "Name kro gave the Deployment and the Service"
}

output "instance_status_command" {
  value       = "kubectl -n ${var.namespace} get ${lower(var.kind)} ${var.name} -o jsonpath='{.status}{\"\\n\"}'"
  description = "Reads the status fields the definition declared, which kro copies out of the objects it created. An empty availableReplicas means the Deployment has not come up yet"
}

output "expanded_objects_command" {
  value       = "kubectl -n ${var.namespace} get deployment,service ${var.workload_name}"
  description = "The Deployment and Service kro built from four lines of instance spec. Neither is declared anywhere in this configuration"
}

output "instance_conditions_command" {
  value       = "kubectl -n ${var.namespace} get ${lower(var.kind)} ${var.name} -o jsonpath='{range .status.conditions[*]}{.type}={.status} {.message}{\"\\n\"}{end}'"
  description = "Where kro reports a failure to create the underlying objects. A forbidden message here is the capability role's cluster access policy, not the definition"
}
