# Every output is a projection of local.outputs in main.tf, which is also what the
# README written onto the VS Code instance is rendered from (rules.md H-2). No value
# expression is written here: an output that built its own value would be missing from
# that README and the apply would succeed either way. The check is a count - the number
# of output blocks here must equal the number of entries in local.outputs.
output "vscode_url" {
  value       = local.outputs.vscode_url.value
  description = "URL of the code-server web UI, served through CloudFront"
}
output "cluster_name" {
  value       = local.outputs.cluster_name.value
  description = "Name of the EKS cluster"
}
output "github_repository_url" {
  value       = local.outputs.github_repository_url.value
  description = "Browser URL of the GitHub repository Terraform created"
}
output "ecr_repository_url" {
  value       = local.outputs.ecr_repository_url.value
  description = "Registry path the pipeline pushes images to"
}
output "argocd_url_command" {
  value       = local.outputs.argocd_url_command.value
  description = "Command printing the Argo CD UI address, which a controller provisions rather than Terraform"
}
output "argocd_password_command" {
  value       = local.outputs.argocd_password_command.value
  description = "Command printing the generated Argo CD admin password"
}
output "argocd_application_command" {
  value       = local.outputs.argocd_application_command.value
  description = "Command showing whether Argo CD has synced the repository"
}
output "edit_index_url" {
  value       = local.outputs.edit_index_url.value
  description = "Direct link to edit index.html, the action that starts the pipeline"
}
output "codebuild_builds_command" {
  value       = local.outputs.codebuild_builds_command.value
  description = "Command listing runner builds"
}
output "codebuild_log_command" {
  value       = local.outputs.codebuild_log_command.value
  description = "Command tailing the runner's build log"
}
output "ecr_images_command" {
  value       = local.outputs.ecr_images_command.value
  description = "Command listing the image tags the pipeline has pushed"
}
output "app_ingress_command" {
  value       = local.outputs.app_ingress_command.value
  description = "Command showing the Ingress Argo CD applied and its ALB address"
}
output "update_kubeconfig_command" {
  value       = local.outputs.update_kubeconfig_command.value
  description = "Command that points kubectl on the VS Code instance at the cluster"
}
