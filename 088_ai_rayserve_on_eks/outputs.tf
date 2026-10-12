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

output "ray_dashboard_port_forward_command" {
  value       = local.outputs.ray_dashboard_port_forward_command.value
  description = "Command that port-forwards the Ray dashboard to localhost from the IDE terminal"
}

output "node_pools_command" {
  value       = local.outputs.node_pools_command.value
  description = "Command that lists the Karpenter pools and node classes"
}

output "nodes_command" {
  value       = local.outputs.nodes_command.value
  description = "Command that lists the nodes with their pool labels and purchase option"
}

output "gpu_capacity_command" {
  value       = local.outputs.gpu_capacity_command.value
  description = "Command that shows how much nvidia.com/gpu capacity the device plugin is advertising"
}

output "ray_service_status_command" {
  value       = local.outputs.ray_service_status_command.value
  description = "Command that shows whether the Ray Serve application reached RUNNING"
}

output "ray_pods_command" {
  value       = local.outputs.ray_pods_command.value
  description = "Command that shows the Ray head and worker pods and the nodes they landed on"
}

output "ingress_command" {
  value       = local.outputs.ingress_command.value
  description = "Command that reads the ALB address the controller attached to the Ray Serve Ingress"
}

output "generate_image_command" {
  value       = local.outputs.generate_image_command.value
  description = "Command template that calls the Stable Diffusion endpoint through the ALB. Run it from the IDE terminal: the ALB is internal unless alb_allow_inbound_from_anywhere is true"
}

output "controller_log_command" {
  value       = local.outputs.controller_log_command.value
  description = "Command that reads the AWS Load Balancer Controller log"
}

output "karpenter_log_command" {
  value       = local.outputs.karpenter_log_command.value
  description = "Command that reads the Karpenter controller log, where an unschedulable pod is explained"
}

output "kuberay_operator_log_command" {
  value       = local.outputs.kuberay_operator_log_command.value
  description = "Command that reads the KubeRay operator log, where a rejected RayService spec is explained"
}

output "update_kubeconfig_command" {
  value       = local.outputs.update_kubeconfig_command.value
  description = "Command that points kubectl on the bastion at the cluster"
}
