# Every output is a projection of local.outputs in main.tf, which is also what the README written
# onto the VS Code instance is rendered from (rules.md H-2). No value expression is written here:
# an output that built its own value would be missing from that README, and nothing would fail to
# say so - the apply would succeed either way. Whether the pattern still holds is checked by
# counting: the number of output blocks here must equal the number of entries in local.outputs.
#
# Four secrets are deliberately absent - Vault's root token and unseal key, Argo CD's admin
# password, the GitHub token and the demo secret. Each is reachable only through a command, because
# this text is also written into a README that an unauthenticated code-server serves
# (rules.md H-2).
#
# description is the one thing repeated, because Terraform rejects an expression there ("Variables
# not allowed") - it has to be a literal.
output "vscode_url" {
  value       = local.outputs.vscode_url.value
  description = "URL to access the code-server web UI on the VS Code EC2 instance"
}
output "cluster_name" {
  value       = local.outputs.cluster_name.value
  description = "Name of the EKS cluster"
}
output "argocd_url" {
  value       = local.outputs.argocd_url.value
  description = "Argo CD UI URL, served through the pre-created NLB the controller adopts from the server Service (rules.md G-3)"
}
output "argocd_password_command" {
  value       = local.outputs.argocd_password_command.value
  description = "Command reading Argo CD's generated admin password out of its Secret. A command rather than the value (rules.md H-2)"
}
output "vault_url" {
  value       = local.outputs.vault_url.value
  description = "Vault UI URL, served through the pre-created ALB the controller adopts from Vault's Ingress (rules.md G-3)"
}
output "vault_token_command" {
  value       = local.outputs.vault_token_command.value
  description = "Command reading Vault's root token and unseal key from the init output the bootstrap step left on the instance"
}
output "vault_status_command" {
  value       = local.outputs.vault_status_command.value
  description = "Command showing whether Vault is initialised and unsealed"
}
output "argocd_repo_server_command" {
  value       = local.outputs.argocd_repo_server_command.value
  description = "Command confirming the repo-server rolled out with the argocd-vault-plugin sidecar"
}
output "argocd_plugin_logs_command" {
  value       = local.outputs.argocd_plugin_logs_command.value
  description = "Command following the plugin sidecar's log, where a sync failure explains itself"
}
output "adopted_load_balancer_check_command" {
  value       = local.outputs.adopted_load_balancer_check_command.value
  description = "Command listing every load balancer tagged for this cluster. Two is correct; more means adoption failed for one of them (rules.md G-3)"
}
output "argocd_app_create_command" {
  value       = local.outputs.argocd_app_create_command.value
  description = "Command creating the Argo CD Application that syncs the seed repository through the plugin"
}
output "seed_repo_path" {
  value       = local.outputs.seed_repo_path.value
  description = "Directory on the instance holding the seed manifests, whose env values are argocd-vault-plugin placeholders"
}
output "source_bucket" {
  value       = local.outputs.source_bucket.value
  description = "Bucket the seed repository zip is uploaded to. Nothing consumes it yet - there is no CodeBuild project or pipeline in this project"
}
output "codestar_connection_status" {
  value       = local.outputs.codestar_connection_status.value
  description = "The CodeStar connection and its status. A new connection is PENDING until the GitHub handshake is completed in the console"
}
output "update_kubeconfig_command" {
  value       = local.outputs.update_kubeconfig_command.value
  description = "Command that points kubectl on the VS Code instance at the cluster"
}
output "storage_class_name" {
  value       = local.outputs.storage_class_name.value
  description = "Name of the gp3 StorageClass Vault's data volume is provisioned from"
}
output "storage_class_check_command" {
  value       = local.outputs.storage_class_check_command.value
  description = "Command that lists the cluster's StorageClasses and which one is default"
}
output "pending_claims_command" {
  value       = local.outputs.pending_claims_command.value
  description = "Command that shows whether Vault's PersistentVolumeClaim bound"
}
output "seed_repository_url" {
  value       = local.outputs.seed_repository_url.value
  description = "Browser URL of the Git repository Argo CD syncs from, created by this configuration"
}
output "seed_repository_files" {
  value       = local.outputs.seed_repository_files.value
  description = "Branch and manifest paths committed to the seed repository"
}
