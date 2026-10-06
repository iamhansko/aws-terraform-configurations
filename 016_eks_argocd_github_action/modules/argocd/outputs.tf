output "namespace" {
  value       = var.namespace
  description = "Namespace Argo CD runs in, re-exposed so the caller's verification commands do not restate it (rules.md B-5)"
}
output "application_name" {
  value       = var.application_name
  description = "Name of the Argo CD Application watching the repository"
}
output "server_url_command" {
  # Prints a URL rather than the bare hostname this used to print, and specifically an
  # http:// one.
  #
  # The scheme is not a detail here. configs.params.server.insecure is true, so
  # argocd-server serves plain HTTP on 8080, and the chart's Service publishes both 80
  # and 443 with *both* mapped to that same 8080 - there is no port on it that speaks
  # TLS. So the load balancer gets a listener on 443 that forwards TLS straight into a
  # plain HTTP server: https:// fails the handshake while the target reports healthy,
  # because a TCP health check on 8080 succeeds either way.
  #
  # Argo CD is conventionally reached over https and browsers increasingly try it first,
  # so emitting a bare hostname left the obvious action broken. Serving this over https
  # properly means terminating TLS at the load balancer with an ACM certificate, which
  # needs a domain this project does not have.
  value       = "echo \"http://$(kubectl -n ${var.namespace} get service ${var.release_name}-server -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')\""
  description = "Command printing the URL of the Argo CD UI. The load balancer is created by the AWS Load Balancer Controller rather than by Terraform, so its address cannot be a Terraform output (rules.md G-1/H-2). http rather than https because the server runs insecure and both Service ports map to its plain HTTP port"
}
output "initial_password_command" {
  value       = "kubectl -n ${var.namespace} get secret argocd-initial-admin-secret -o jsonpath='{.data.password}' | base64 -d; echo"
  description = "Command printing the generated admin password. Exposed as a command rather than a value: putting the password in a Terraform output would write it to state and to the README on disk (rules.md H-2)"
}
output "application_status_command" {
  value       = "kubectl -n ${var.namespace} get application ${var.application_name} -o custom-columns=SYNC:.status.sync.status,HEALTH:.status.health.status"
  description = "Command showing whether Argo CD has synced the repository. Synced/Healthy is the end state; OutOfSync means it has seen a commit it has not applied yet"
}
