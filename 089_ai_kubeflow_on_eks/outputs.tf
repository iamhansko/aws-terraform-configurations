# Every value here is a projection of local.outputs in main.tf. No output in this file
# builds its own expression: the same map feeds the README written onto the bastion, and an
# output declared outside it would be missing from that README with nothing to signal the
# gap (rules.md H-2).
#
# description is the one thing that cannot come from the map. Terraform rejects an
# expression in an output's description ("Variables not allowed"), so the wording is
# literal in both places while the value stays in one.

output "vscode_port_forward_command" {
  value       = local.outputs.vscode_port_forward_command.value
  description = "Run on your own machine with the AWS CLI and the Session Manager plugin installed, and keep it running; while it does, localhost on the port it names is the code-server IDE on the bastion. The tunnel uses the SSM agent's outbound connection, so it needs no inbound rule on the bastion"
}

output "vscode_url" {
  value       = local.outputs.vscode_url.value
  description = "CloudFront URL of the code-server IDE on the bastion"
}

output "cluster_name" {
  value       = local.outputs.cluster_name.value
  description = "Name of the EKS cluster, which is also the name Karpenter is configured with"
}

output "kubeflow_version" {
  value       = local.outputs.kubeflow_version.value
  description = "Git tag of the Kubeflow manifests that were installed"
}

output "kubeflow_dashboard_port_forward_command" {
  value       = local.outputs.kubeflow_dashboard_port_forward_command.value
  description = "Command that port-forwards the Kubeflow dashboard to localhost from the IDE terminal"
}

output "node_pools_command" {
  value       = local.outputs.node_pools_command.value
  description = "Command that lists the Karpenter pools and node classes"
}

output "kubeflow_pods_command" {
  value       = local.outputs.kubeflow_pods_command.value
  description = "Command that shows Kubeflow's control plane pods"
}

output "kubeflow_claims_command" {
  value       = local.outputs.kubeflow_claims_command.value
  description = "Command that shows whether Kubeflow's persistent volume claims reached Bound"
}

output "gpu_capacity_command" {
  value       = local.outputs.gpu_capacity_command.value
  description = "Command that shows how much nvidia.com/gpu capacity the device plugin is advertising"
}

output "nodes_command" {
  value       = local.outputs.nodes_command.value
  description = "Command that lists the nodes with their pool labels and purchase option"
}

output "karpenter_log_command" {
  value       = local.outputs.karpenter_log_command.value
  description = "Command that reads the Karpenter controller log, where an unschedulable pod is explained"
}

output "controller_log_command" {
  value       = local.outputs.controller_log_command.value
  description = "Command that reads the AWS Load Balancer Controller log"
}

output "alb_security_group_id" {
  value       = local.outputs.alb_security_group_id.value
  description = "ID of the frontend security group prepared for an Ingress in front of the Kubeflow gateway. It admits the bastion rather than 0.0.0.0/0 by default, so that Ingress should be scheme internal"
}

output "update_kubeconfig_command" {
  value       = local.outputs.update_kubeconfig_command.value
  description = "Command that points kubectl on the bastion at the cluster"
}
output "storage_class_name" {
  value       = local.outputs.storage_class_name.value
  description = "Name of the default gp3 StorageClass Kubeflow's volume claims resolve through"
}
output "storage_class_check_command" {
  value       = local.outputs.storage_class_check_command.value
  description = "Command that lists the cluster's StorageClasses and which one is default"
}
output "pending_claims_command" {
  value       = local.outputs.pending_claims_command.value
  description = "Command that shows whether Kubeflow's PersistentVolumeClaims bound"
}
