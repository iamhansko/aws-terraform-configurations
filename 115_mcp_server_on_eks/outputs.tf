# Every value here is a projection of local.outputs in main.tf. No output in this file builds
# its own expression: the same map feeds the README written onto the workbench, and an output
# declared outside it would be missing from that README with nothing to signal the gap
# (rules.md H-2).
#
# description is the one thing that cannot come from the map. Terraform rejects an expression
# in an output's description ("Variables not allowed"), so the wording is literal in both
# places while the value stays in one.
#
# Nothing here is sensitive - the MCP endpoint has no credential in front of it at all, which
# is what the security_warning entry is for rather than a sensitive output.

output "vscode_url" {
  value       = local.outputs.vscode_url.value
  description = "URL of the code-server web UI on the workbench instance"
}

output "mcp_server_url" {
  value       = local.outputs.mcp_server_url.value
  description = "URL an IDE puts in its mcp.json as a streamable-http MCP server"
}

output "mcp_json" {
  value       = local.outputs.mcp_json.value
  description = "The mcp.json fragment for this endpoint, rendered from the URL above"
}

output "security_warning" {
  value       = local.outputs.security_warning.value
  description = "Command that lists what may reach the MCP load balancer, which is the only access control in front of a cluster-admin endpoint"
}

output "cluster_name" {
  value       = local.outputs.cluster_name.value
  description = "Name of the EKS cluster, which is also the elbv2.k8s.aws/cluster tag on the pre-created load balancer"
}

output "image_uri" {
  value       = local.outputs.image_uri.value
  description = "Full image reference CodeBuild pushes and the Deployment pulls"
}

output "build_status_command" {
  value       = local.outputs.build_status_command.value
  description = "Command that shows the most recent image build's status and failing phase"
}

output "images_check_command" {
  value       = local.outputs.images_check_command.value
  description = "Command that lists the images in the ECR repository"
}

output "deployment_status_command" {
  value       = local.outputs.deployment_status_command.value
  description = "Command that shows the MCP server Deployment"
}

output "ingress_status_command" {
  value       = local.outputs.ingress_status_command.value
  description = "Command that shows the Ingress and the load balancer address attached to it"
}

output "adoption_check_command" {
  value       = local.outputs.adoption_check_command.value
  description = "Command that lists every load balancer tagged for this cluster; more than one means adoption failed"
}

output "status_probe_command" {
  value       = local.outputs.status_probe_command.value
  description = "Command that requests the proxy's health path through the load balancer"
}

output "pod_log_command" {
  value       = local.outputs.pod_log_command.value
  description = "Command that reads the MCP server's log, where an AWS access denial appears"
}

output "update_kubeconfig_command" {
  value       = local.outputs.update_kubeconfig_command.value
  description = "Command that points kubectl on the workbench at the cluster"
}
