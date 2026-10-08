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
  description = "Name of the EKS capability. AWS installs and runs the kro controller itself, so there is no Helm release here and nothing on the cluster for this configuration to upgrade. The _monolithic template named this one kro and asked for type ACK, which installed the wrong controllers without reporting anything"
}

output "capability_role_arn" {
  value       = local.outputs.capability_role_arn.value
  description = "The role AWS assumes to run kro. It carries no managed policies: kro calls no AWS API of its own, and what it needs is Kubernetes permission, which comes from the access policy association below"
}

output "capability_status_command" {
  value       = local.outputs.capability_status_command.value
  description = "CREATING for several minutes is normal. Stuck in CREATING usually means there was no schedulable node capacity when it started, because the controller it installs is a pod. Check the type column too - it should say KRO"
}

output "definition_status_command" {
  value       = local.outputs.definition_status_command.value
  description = "Active means kro accepted the graph and generated a CRD for the new kind. Inactive means it rejected it, and the reason is in status.conditions rather than anywhere apply would show it"
}

output "generated_api_command" {
  value       = local.outputs.generated_api_command.value
  description = "A kind that did not exist before this definition. An SSM step waited for exactly this before the instance was applied, because the CRD is generated between two applies"
}

output "demo_instance_status_command" {
  value       = local.outputs.demo_instance_status_command.value
  description = "The status fields the definition declared, copied out of the objects kro created. A forbidden message in the conditions is the capability role's cluster access policy, not the definition"
}

output "expanded_objects_command" {
  value       = local.outputs.expanded_objects_command.value
  description = "The point of kro: a Deployment and a Service that four lines of instance spec produced, neither of them declared anywhere in this configuration"
}

output "capability_access_entry_command" {
  value       = local.outputs.capability_access_entry_command.value
  description = "Created by EKS rather than by this configuration, which is why the root declares only a policy association and never an access entry. AmazonEKSKROPolicy is the baseline it comes with, and it covers only definitions and their instances - AmazonEKSClusterAdminPolicy is what lets kro create the objects a definition composes"
}

output "node_check_command" {
  value       = local.outputs.node_check_command.value
  description = "Two t3.large nodes. The capability's controller runs on them, so a capability that never becomes ACTIVE is worth checking here first"
}

output "update_kubeconfig_command" {
  value       = local.outputs.update_kubeconfig_command.value
  description = "User data already ran this, so kubectl works out of the box. Re-run it if the kubeconfig is ever lost"
}
