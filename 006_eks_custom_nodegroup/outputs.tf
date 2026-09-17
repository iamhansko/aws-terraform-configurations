# Every output is a projection of local.outputs in main.tf, which is also what
# the README written onto the VS Code instance is rendered from (rules.md #35).
# No value expression is written here: an output that built its own value would
# be missing from that README, and nothing would fail to tell anyone - the apply
# would succeed either way. Whether this pattern still holds is checked by
# counting: the number of output blocks here must equal the number of entries in
# local.outputs.
#
# description is the one thing repeated, because Terraform rejects an expression
# there ("Variables not allowed") - it has to be a literal.
output "vscode_url" {
  value       = local.outputs.vscode_url.value
  description = "URL to access the code-server web UI on the VS Code EC2 instance"
}
output "cluster_name" {
  value       = local.outputs.cluster_name.value
  description = "Name of the EKS cluster"
}
output "cluster_endpoint" {
  value       = local.outputs.cluster_endpoint.value
  description = "API server endpoint of the EKS cluster"
}
output "app_node_group_name" {
  value       = local.outputs.app_node_group_name.value
  description = "Name of the managed node group carrying application workloads"
}
output "addon_node_group_name" {
  value       = local.outputs.addon_node_group_name.value
  description = "Name of the managed node group carrying cluster addons"
}
output "app_node_group_launch_template_id" {
  value       = local.outputs.app_node_group_launch_template_id.value
  description = "ID of the custom launch template backing the application node group, the piece this project demonstrates"
}
output "ecr_repository_url" {
  value       = local.outputs.ecr_repository_url.value
  description = "URL of the ECR repository the VS Code EC2 instance pushes the sample image to"
}
output "kube_ops_view_service_command" {
  value       = local.outputs.kube_ops_view_service_command.value
  description = "Command that shows the kube-ops-view Service, including the NLB's DNS name in EXTERNAL-IP once the AWS Load Balancer Controller has reconciled it"
}
output "kube_ops_view_endpoint_command" {
  value       = local.outputs.kube_ops_view_endpoint_command.value
  description = "Command that prints just the NLB's DNS name. Terraform cannot output the address itself: the load balancer is created by the controller in response to the Service, not by a Terraform resource"
}
output "kube_ops_view_fetch_command" {
  value       = local.outputs.kube_ops_view_fetch_command.value
  description = "Command that fetches the dashboard through the NLB, or null when kube_ops_view_service_type is not LoadBalancer"
}
output "kube_ops_view_port_forward_command" {
  value       = local.outputs.kube_ops_view_port_forward_command.value
  description = "Command to reach the kube-ops-view dashboard on http://localhost:8080 without going through a load balancer, which is how to use it when kube_ops_view_service_type is ClusterIP"
}
output "hpa_load_generator_command" {
  value       = local.outputs.hpa_load_generator_command.value
  description = "Command that drives CPU load into the demo Service so the HorizontalPodAutoscaler, and then the cluster autoscaler, scale up"
}
