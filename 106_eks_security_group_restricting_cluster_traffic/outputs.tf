# Every value here is a projection of local.outputs in main.tf. No output in this
# file builds its own expression: the same map feeds the README written onto the
# workbench, and an output declared outside it would be missing from that README
# with nothing to signal the gap (rules.md H-2).
#
# description is the one thing that cannot come from the map. Terraform rejects an
# expression in an output's description ("Variables not allowed"), so the wording is
# literal in both places while the value stays in one.

output "vscode_url" {
  value       = local.outputs.vscode_url.value
  description = "URL of the code-server web UI on the workbench instance, which is the only place kubectl reaches this cluster"
}

output "cluster_name" {
  value       = local.outputs.cluster_name.value
  description = "Name of the EKS cluster"
}

output "cluster_endpoint" {
  value       = local.outputs.cluster_endpoint.value
  description = "Private API server endpoint, which resolves only inside the VPC"
}

output "cluster_security_group_id" {
  value       = local.outputs.cluster_security_group_id.value
  description = "ID of the EKS-managed cluster security group, which is the group this project restricts traffic out of"
}

output "vpc_endpoint_security_group_id" {
  value       = local.outputs.vpc_endpoint_security_group_id.value
  description = "ID of the security group in front of the interface VPC endpoints"
}

output "s3_prefix_list_id" {
  value       = local.outputs.s3_prefix_list_id.value
  description = "Prefix list ID of the S3 gateway endpoint, which is the destination of the cluster's S3 egress rule"
}

output "controller_image_repository" {
  value       = local.outputs.controller_image_repository.value
  description = "Pull-through cache repository the load balancer controller image is pulled from, since ECR Public is unreachable once the cluster's blanket egress rule is revoked"
}

output "cluster_security_group_rules_command" {
  value       = local.outputs.cluster_security_group_rules_command.value
  description = "Command that lists every rule on the cluster security group, for confirming the allow-all egress rule is gone and for comparing before and after a cluster update"
}

output "endpoint_check_command" {
  value       = local.outputs.endpoint_check_command.value
  description = "Command that shows the state of each VPC endpoint"
}

output "node_status_command" {
  value       = local.outputs.node_status_command.value
  description = "Command that shows whether the nodes joined the cluster Ready"
}

output "controller_status_command" {
  value       = local.outputs.controller_status_command.value
  description = "Command that shows the AWS Load Balancer Controller Deployment, which is not in Terraform state"
}

output "controller_log_command" {
  value       = local.outputs.controller_log_command.value
  description = "Command that reads the load balancer controller log, where an AWS-side permission problem appears"
}

output "revoke_cluster_egress_command" {
  value       = local.outputs.revoke_cluster_egress_command.value
  description = "Command that revokes the cluster security group's allow-all egress rule, for re-running by hand after an EKS version update puts it back"
}

output "update_kubeconfig_command" {
  value       = local.outputs.update_kubeconfig_command.value
  description = "Command that points kubectl on the workbench at the cluster"
}
