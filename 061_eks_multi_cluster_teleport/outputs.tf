# Every value here is a projection of local.outputs in main.tf. No output declares its
# own value expression: the same map is what the README on the VS Code instance is
# rendered from, so an output written directly here would be missing from that README and
# nothing would report it - the apply succeeds either way (rules.md H-2).
#
# description is the one exception. Terraform does not allow an expression there
# ("Variables not allowed"), so the wording exists as a literal in both places while the
# value still exists in only one.
output "vscode_url" {
  value       = local.outputs.vscode_url.value
  description = "Open the IDE here. Its terminal has kubectl, helm and tsh"
}
output "cluster_name" {
  value       = local.outputs.cluster_name.value
  description = "Name of the EKS cluster, and the name it is registered under inside Teleport"
}
output "cluster_endpoint" {
  value       = local.outputs.cluster_endpoint.value
  description = "API server endpoint - the direct access path Teleport exists to replace"
}
output "teleport_url" {
  value       = local.outputs.teleport_url.value
  description = "The Teleport web UI, once the DNS records resolve and the certificate has been issued"
}
output "teleport_version" {
  value       = local.outputs.teleport_version.value
  description = "Chart version, which is also the Teleport version and the version its DynamoDB state belongs to"
}
output "session_bucket" {
  value       = local.outputs.session_bucket.value
  description = "Bucket session recordings are written to: versioned, encrypted and closed to public access"
}
output "state_tables" {
  value       = local.outputs.state_tables.value
  description = "The DynamoDB tables Teleport creates for cluster state and the audit log"
}
output "add_user_command" {
  value       = local.outputs.add_user_command.value
  description = "Run by the operator from this terminal, with the AWS credentials terraform apply used - not from the VS Code instance. Points kubectl at the cluster, creates the first user with the Kubernetes group Teleport impersonates for them, and prints a single-use invite link here and nowhere else. A command rather than an output, so the credential never reaches state"
}
output "kube_login_command" {
  value       = local.outputs.kube_login_command.value
  description = "Authenticates to Teleport as the account add_user_command created and gets a kubeconfig, with no IAM credential for the person doing it"
}
output "teleport_status_command" {
  value       = local.outputs.teleport_status_command.value
  description = "Teleport's own view of itself, read from the auth pod. Reaching it proves the DynamoDB backend is readable"
}
output "certificate_command" {
  value       = local.outputs.certificate_command.value
  description = "Whether the certificate was issued. Ready=False is the usual reason the proxy never becomes ready"
}
output "issuance_chain_command" {
  value       = local.outputs.issuance_chain_command.value
  description = "The whole cert-manager chain in one command; the last object present is where issuance stopped"
}
output "adopted_load_balancer_check_command" {
  value       = local.outputs.adopted_load_balancer_check_command.value
  description = "Lists every load balancer tagged for this cluster. One is correct; two means the pre-created one was not adopted (rules.md G-3)"
}
output "proxy_hostname_command" {
  value       = local.outputs.proxy_hostname_command.value
  description = "The address the controller attached to the proxy Service, for comparison against the DNS records"
}
output "dns_records" {
  value       = local.outputs.dns_records.value
  description = "The alias records pointing at the pre-created load balancer - Terraform resources, which is only possible because Terraform owns the load balancer (rules.md G-3)"
}
output "recording_list_command" {
  value       = local.outputs.recording_list_command.value
  description = "What has actually been recorded. Empty after a session means recordings are going somewhere else"
}
output "update_kubeconfig_command" {
  value       = local.outputs.update_kubeconfig_command.value
  description = "Re-points kubectl on the instance at the cluster directly, for when Teleport itself is what is broken"
}
output "grant_kubernetes_access_command" {
  value       = local.outputs.grant_kubernetes_access_command.value
  description = "Run by the operator from this terminal, like add_user_command. Gives a user created without --kubernetes-groups the Kubernetes group, so Teleport stops refusing their kubectl requests. Takes effect at their next tsh login"
}
output "reset_user_command" {
  value       = local.outputs.reset_user_command.value
  description = "Run by the operator from this terminal when add_user_command answers that the user already exists - an expired link, or an account left in the DynamoDB tables by an earlier deployment, which terraform destroy does not remove. Discards the account's password and second factor devices and prints a new invite link"
}
