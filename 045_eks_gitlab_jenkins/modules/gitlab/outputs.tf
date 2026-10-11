output "release_name" {
  value       = helm_release.gitlab.name
  description = "Name of the GitLab Helm release"
}

output "release_status" {
  value       = helm_release.gitlab.status
  description = "Status the provider last recorded for the release. A failed release stays in the cluster without being in state, and the next apply then reports \"cannot re-use a name that is still in use\" rather than the original cause (rules.md E-7)"
}

output "namespace" {
  value       = var.namespace
  description = "Namespace the release lives in, re-exposed so callers do not restate it (rules.md B-5)"
}

output "ingress_service_name" {
  value       = var.ingress_service_name
  description = "Name of the Service the bundled nginx-ingress controller creates, re-exposed so callers do not restate it (rules.md B-5). This is the Service the AWS Load Balancer Controller reconciles into a load balancer"
}

output "stack_tag" {
  value       = var.stack_tag
  description = "The <namespace>/<name> value the AWS Load Balancer Controller writes into its service.k8s.aws/stack tag. A pre-created load balancer has to carry exactly this to be adopted instead of duplicated, so it is derived here rather than restated by the caller (rules.md B-5/G-3)"
}

output "url" {
  value       = "https://gitlab.${var.domain}"
  description = "GitLab web URL. Resolves only once the wildcard DNS record points at the load balancer"
}

output "initial_root_password_command" {
  value       = "kubectl -n ${var.namespace} get secret ${var.release_name}-gitlab-initial-root-password -o jsonpath='{.data.password}' | base64 --decode ; echo"
  description = "Command that prints the generated root password. The chart writes it into a Secret, so it is read from the cluster rather than exposed as a Terraform output"
}

output "load_balancer_hostname_command" {
  value       = "kubectl -n ${var.namespace} get service ${var.ingress_service_name} -o jsonpath='{.status.loadBalancer.ingress[0].hostname}'"
  description = "Command that reads the load balancer address the controller attached. Compare it against the pre-created load balancer's DNS name: two different names mean the adoption tags did not match and a second load balancer was built (rules.md G-3)"
}
