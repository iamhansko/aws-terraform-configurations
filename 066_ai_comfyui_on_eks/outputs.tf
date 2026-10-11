# Values are all projections of local.outputs in main.tf, so no expression is written twice and the README
# the SSM association writes cannot fall behind this file (rules.md B-5/H-2).
#
# description is the one thing that cannot come from the map: Terraform rejects an expression in an output's
# description with "Variables not allowed", so the wording exists literally in both places. The values do
# not.
output "vscode_port_forward_command" {
  value       = local.outputs.vscode_port_forward_command.value
  description = "Run on your own machine with the AWS CLI and the Session Manager plugin installed, and keep it running - vscode_url answers only while it does"
}
output "vscode_url" {
  value       = local.outputs.vscode_url.value
  description = "The IDE: localhost through the port forward, or the instance's public address when allow_inbound_from_anywhere is true. No authentication, AdministratorAccess behind it"
}
output "comfyui_url" {
  value       = local.outputs.comfyui_url.value
  description = "ComfyUI through CloudFront and the VPC origin. No authentication in front of it, as in the blueprint"
}
output "cluster_name" {
  value       = local.outputs.cluster_name.value
  description = "Name of the EKS cluster"
}
output "image_build_status_command" {
  value       = local.outputs.image_build_status_command.value
  description = "Status of the most recent ComfyUI image build"
}
output "model_download_status_command" {
  value       = local.outputs.model_download_status_command.value
  description = "Status of the model download, which the apply starts and does not wait for"
}
output "models_in_bucket_command" {
  value       = local.outputs.models_in_bucket_command.value
  description = "How many models have landed in the models bucket so far, and their total size"
}
output "gpu_nodes_command" {
  value       = local.outputs.gpu_nodes_command.value
  description = "The cluster's nodes with instance type, capacity type and Karpenter pool"
}
output "gpu_capacity_command" {
  value       = local.outputs.gpu_capacity_command.value
  description = "nvidia.com/gpu each node advertises"
}
output "comfyui_pods_command" {
  value       = local.outputs.comfyui_pods_command.value
  description = "The ComfyUI pod and the node it runs on"
}
output "comfyui_logs_command" {
  value       = local.outputs.comfyui_logs_command.value
  description = "ComfyUI's log"
}
output "alb_dns_name" {
  value       = local.outputs.alb_dns_name.value
  description = "DNS name of the internal ALB Terraform created and the controller adopted"
}
output "alb_stack_tag" {
  value       = local.outputs.alb_stack_tag.value
  description = "The ingress.k8s.aws/stack value the ALB carries, which has to match the Ingress for adoption (rules.md G-3)"
}
output "ingress_address_command" {
  value       = local.outputs.ingress_address_command.value
  description = "The address the controller attached the Ingress to - should equal alb_dns_name"
}
output "comfyui_port_forward_command" {
  value       = local.outputs.comfyui_port_forward_command.value
  description = "Reaches ComfyUI from the workbench without CloudFront or the ALB"
}
output "model_sync_logs_command" {
  value       = local.outputs.model_sync_logs_command.value
  description = "The model sync Lambda's last hour of activity"
}
output "karpenter_log_command" {
  value       = local.outputs.karpenter_log_command.value
  description = "Karpenter's log, where an unschedulable pod is explained"
}
output "controller_log_command" {
  value       = local.outputs.controller_log_command.value
  description = "The load balancer controller's log"
}
output "rebuild_image_command" {
  value       = local.outputs.rebuild_image_command.value
  description = "Starts an image rebuild by hand"
}
output "update_kubeconfig_command" {
  value       = local.outputs.update_kubeconfig_command.value
  description = "Command that points kubectl at the cluster"
}
output "teardown_command" {
  value       = local.outputs.teardown_command.value
  description = "One terraform destroy removes everything. With bucket_force_destroy true it deletes the generated images and the downloaded models with their buckets"
}
