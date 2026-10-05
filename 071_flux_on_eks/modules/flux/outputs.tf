output "namespace" {
  value       = var.namespace
  description = "Namespace the controllers run in, re-exposed so the objects pointed at them name one value rather than two that have to agree (rules.md B-5)"
}
output "release_name" {
  value       = helm_release.flux.name
  description = "Name of the Helm release, read back off the resource so it reflects what was installed"
}
output "chart_version" {
  value       = var.chart_version
  description = "Chart version installed, re-exposed so the caller's outputs report what was asked for rather than restating it (rules.md B-5)"
}
output "controllers_check_command" {
  value       = "kubectl -n ${var.namespace} get deploy"
  description = "The controller Deployments. All of them Available is the precondition for every other check in this project - a GitRepository with no source-controller sits with no status at all"
}
