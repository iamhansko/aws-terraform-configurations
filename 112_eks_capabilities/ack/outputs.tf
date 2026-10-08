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
  description = "Name of the EKS capability. AWS installs and runs the ACK controllers itself, so there is no Helm release here and nothing on the cluster for this configuration to upgrade"
}

output "capability_role_arn" {
  value       = local.outputs.capability_role_arn.value
  description = "The role AWS assumes to run ACK, and therefore the permission boundary of every ACK custom resource on this cluster. It carries AdministratorAccess by default, which means anyone who can create a custom resource here can create any AWS resource ACK supports"
}

output "capability_status_command" {
  value       = local.outputs.capability_status_command.value
  description = "CREATING for several minutes is normal. Stuck in CREATING usually means there was no schedulable node capacity when it started, because the controllers it installs are pods"
}

output "crd_check_command" {
  value       = local.outputs.crd_check_command.value
  description = "The capability installs over 200 CRDs covering more than 50 AWS services. This is the S3 one, which the demo below uses"
}

output "demo_bucket_status_command" {
  value       = local.outputs.demo_bucket_status_command.value
  description = "ACK.ResourceSynced=True means the controller called S3 and S3 accepted it. False carries the AWS error in its message - an access denied here is the capability role's policies, not the cluster"
}

output "demo_bucket_check_command" {
  value       = local.outputs.demo_bucket_check_command.value
  description = "The point of ACK: a Kubernetes object produced a real AWS resource. Deleting the Kubernetes object deletes this bucket, which is why the object is a Terraform resource rather than something applied by hand"
}

output "capability_access_entry_command" {
  value       = local.outputs.capability_access_entry_command.value
  description = "Created by EKS rather than by this configuration, which is why the root declares only a policy association and never an access entry. AmazonEKSACKPolicy is the baseline it comes with"
}

output "node_check_command" {
  value       = local.outputs.node_check_command.value
  description = "Two t3.large nodes. The capability's controllers run on them, so a capability that never becomes ACTIVE is worth checking here first"
}

output "update_kubeconfig_command" {
  value       = local.outputs.update_kubeconfig_command.value
  description = "User data already ran this, so kubectl works out of the box. Re-run it if the kubeconfig is ever lost"
}
