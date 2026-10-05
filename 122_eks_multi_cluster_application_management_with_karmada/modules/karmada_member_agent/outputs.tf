output "cluster_name" {
  value       = var.cluster_name
  description = "The name this member is registered under, re-exposed so the PropagationPolicy that targets it names the same string rather than restating it (rules.md B-5). A clusterName in a policy that matches no Cluster object is not an error - the policy is accepted and simply schedules nothing"
}
output "release_name" {
  value       = helm_release.karmada_agent.name
  description = "Name of the agent's Helm release in the member cluster"
}
output "namespace" {
  value       = helm_release.karmada_agent.namespace
  description = "Namespace the agent runs in inside the member cluster"
}
output "agent_logs_command" {
  value       = "kubectl -n ${var.namespace} logs deploy/${var.release_name} --tail 50"
  description = "The agent's own log, read against the member cluster rather than the control plane. This is where a registration that never appears explains itself: a TLS error means the Karmada certificate does not carry the load balancer's name as a SAN, a timeout means the member's nodes cannot reach that endpoint, and Forbidden means the client certificate's groups are wrong"
}
output "registration_check_command" {
  value       = "kubectl get cluster ${var.cluster_name} -o jsonpath='{.spec.syncMode}{\"  \"}{.status.conditions[?(@.type==\"Ready\")].status}{\"\\n\"}'"
  description = "Whether this member registered and is Ready, read against the Karmada API server. Expect \"Pull  True\". Push is what the guidance installer's karmadactl join produced instead - see main.tf for why this module cannot"
}
