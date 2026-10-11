output "release_name" {
  value       = helm_release.jenkins.name
  description = "Name of the Jenkins Helm release"
}

output "release_status" {
  value       = helm_release.jenkins.status
  description = "Status the provider last recorded for the release"
}

output "namespace" {
  value       = var.namespace
  description = "Namespace the release lives in, re-exposed so callers do not restate it (rules.md B-5)"
}

output "admin_username" {
  value       = var.admin_username
  description = "Jenkins administrator login name. The password is deliberately not an output - it is read from the chart's Secret instead"
}

output "ingress_class_name" {
  value       = var.ingress_class_name
  description = "IngressClass this release's Ingress asks for, re-exposed so a mismatch with the controller that created the class is visible in outputs (rules.md B-5)"
}

output "admin_password_command" {
  value       = "kubectl -n ${var.namespace} get secret ${var.release_name} -o jsonpath='{.data.jenkins-admin-password}' | base64 --decode ; echo"
  description = "Command that reads the administrator password back out of the chart's Secret, which is where it lives rather than in Terraform state output"
}

output "ingress_status_command" {
  value       = "kubectl -n ${var.namespace} get ingress ${var.release_name}"
  description = "Command that shows the Ingress and its class. An empty CLASS column means the class was never set and no controller will claim it"
}
