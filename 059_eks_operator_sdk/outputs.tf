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
  description = "Open the IDE here. The generated operator project is already on disk"
}
output "cluster_name" {
  value       = local.outputs.cluster_name.value
  description = "Name of the EKS cluster"
}
output "cluster_endpoint" {
  value       = local.outputs.cluster_endpoint.value
  description = "API server endpoint. Reached from the bastion rather than by a Terraform provider - everything Kubernetes-side here is applied by make deploy"
}
output "operator_project" {
  value       = local.outputs.operator_project.value
  description = "Where operator-sdk scaffolded the operator on the instance"
}
output "operator_image" {
  value       = local.outputs.operator_image.value
  description = "The operator image, built on the bastion and pulled by the controller. Terraform owns the repository but not the image"
}
output "ecr_image_list_command" {
  value       = local.outputs.ecr_image_list_command.value
  description = "What is in the repository. Empty means the build step never reached the push"
}
output "controller_status_command" {
  value       = local.outputs.controller_status_command.value
  description = "The controller Deployment make deploy created, in the namespace derived from the project name"
}
output "crd_command" {
  value       = local.outputs.crd_command.value
  description = "The custom resource definition the generated API produced"
}
output "custom_resource_command" {
  value       = local.outputs.custom_resource_command.value
  description = "The sample custom resource. No status means the controller is running but not reconciling"
}
output "managed_workload_command" {
  value       = local.outputs.managed_workload_command.value
  description = "The workload the controller created in response to that resource - the operator actually working"
}
output "controller_log_command" {
  value       = local.outputs.controller_log_command.value
  description = "The reconcile loop's own account, where an RBAC gap in the generated role shows up"
}
output "scale_command" {
  value       = local.outputs.scale_command.value
  description = "Edits the custom resource so the controller converges the workload to match"
}
output "rebuild_command" {
  value       = local.outputs.rebuild_command.value
  description = "Rebuilds and redeploys after changing the controller code, without involving Terraform"
}
output "update_kubeconfig_command" {
  value       = local.outputs.update_kubeconfig_command.value
  description = "Re-points kubectl on the instance at the cluster. User data already ran this"
}
