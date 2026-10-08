# Every value here is a projection of local.outputs in main.tf, which the README written onto the
# workbench renders from the same map - so no value expression exists twice (rules.md B-5/H-2).
#
# The descriptions are the one thing that cannot be projected: Terraform does not allow an expression
# in an output description ("Variables not allowed"), so the wording is repeated here as a literal
# while the values are not.

output "vscode_url" {
  value       = local.outputs.vscode_url.value
  description = "Open the IDE here and run every command below from its terminal"
}

output "cluster_name" {
  value       = local.outputs.cluster_name.value
  description = "Name of the EKS cluster the capability is installed on"
}

output "capability_name" {
  value       = local.outputs.capability_name.value
  description = "Name of the EKS capability. AWS installs and runs Argo CD itself, so there is no Helm release here and nothing on the cluster for this configuration to upgrade"
}

output "argocd_server_url" {
  value       = local.outputs.argocd_server_url.value
  description = "The managed Argo CD API server, assigned by AWS rather than configured here. Signing in goes through IAM Identity Center - Argo CD as a capability has no local users, so there is no admin password to look up"
}

output "identity_center_console" {
  value       = local.outputs.identity_center_console.value
  description = "Where the created user's one-time password is sent from, and where more users and groups are added. The default email is example.com, so change identity_center_user_email before expecting to receive it"
}

output "argocd_admin_user" {
  value       = local.outputs.argocd_admin_user.value
  description = "The identity store user mapped to Argo CD's ADMIN role. A role mapping takes the user id rather than the name, which is why the user is created here rather than left to the console"
}

output "capability_status_command" {
  value       = local.outputs.capability_status_command.value
  description = "CREATING for several minutes is normal. Rejected immediately usually means the aws_idc block was missing, because Argo CD requires Identity Center; stuck in CREATING usually means there was no schedulable node capacity when it started"
}

output "argocd_pods_command" {
  value       = local.outputs.argocd_pods_command.value
  description = "The components the capability installed into its namespace. Nothing here is declared in this configuration - AWS owns these pods"
}

output "application_status_command" {
  value       = local.outputs.application_status_command.value
  description = "Synced and Healthy is the end state. OutOfSync that never clears is usually the capability role's cluster access policy, since its baseline policies only cover the Argo CD namespace"
}

output "deployed_objects_command" {
  value       = local.outputs.deployed_objects_command.value
  description = "The point of the capability: objects from a git repository, in a namespace Argo CD created, none of it declared here. Edit the Deployment with kubectl and self-heal puts it back"
}

output "capability_access_entry_command" {
  value       = local.outputs.capability_access_entry_command.value
  description = "Created by EKS rather than by this configuration, which is why the root declares only a policy association and never an access entry. AmazonEKSArgoCDClusterPolicy and AmazonEKSArgoCDPolicy are the baselines it comes with, and neither grants write access outside the Argo CD namespace"
}

output "node_check_command" {
  value       = local.outputs.node_check_command.value
  description = "Two t3.large nodes. Argo CD's components run on them, so a capability that never becomes ACTIVE is worth checking here first"
}

output "update_kubeconfig_command" {
  value       = local.outputs.update_kubeconfig_command.value
  description = "User data already ran this, so kubectl works out of the box. Re-run it if the kubeconfig is ever lost"
}
