output "name" {
  value       = var.name
  description = "Name of the ResourceGraphDefinition, re-exposed so the caller's wait step and verification commands read one value (rules.md B-5)"
}

output "kind" {
  value       = var.kind
  description = "Kind of the new API this definition creates"
}

output "api_version" {
  value       = "kro.run/${var.api_version}"
  description = "Full apiVersion of the new API, which is what an instance manifest has to carry"
}

output "resource_name" {
  # Lowercased kind, which is what kubectl accepts as a resource name through discovery. Used to
  # test servability without having to guess how kro pluralised the kind for the CRD.
  value       = lower(var.kind)
  description = "Lowercased kind, usable directly as a kubectl resource name once the generated CRD is served"
}

output "status_command" {
  value       = "kubectl get resourcegraphdefinition ${var.name} -o jsonpath='{.status.state}{\"\\n\"}'"
  description = "Reads the definition's state. Active means kro created the CRD and is watching for instances; Inactive carries the reason in status.conditions"
}

output "conditions_command" {
  value       = "kubectl get resourcegraphdefinition ${var.name} -o jsonpath='{range .status.conditions[*]}{.type}={.status} {.message}{\"\\n\"}{end}'"
  description = "Where a rejected definition explains itself - a bad kro expression or an unresolvable reference between templates shows up here rather than as an error from apply"
}
