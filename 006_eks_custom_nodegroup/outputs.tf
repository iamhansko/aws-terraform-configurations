output "vscode_url" {
  value       = module.vscode_ec2.vscode_url
  description = "URL to access the code-server web UI on the VS Code EC2 instance"
}
output "cluster_name" {
  value       = module.eks_cluster.cluster_name
  description = "Name of the EKS cluster"
}
output "cluster_endpoint" {
  value       = module.eks_cluster.cluster_endpoint
  description = "API server endpoint of the EKS cluster"
}
output "app_node_group_name" {
  value       = module.eks_app_node_group.node_group_name
  description = "Name of the managed node group carrying application workloads"
}
output "addon_node_group_name" {
  value       = module.eks_addon_node_group.node_group_name
  description = "Name of the managed node group carrying cluster addons"
}
output "app_node_group_launch_template_id" {
  value       = module.eks_app_node_group.launch_template_id
  description = "ID of the custom launch template backing the application node group, the piece this project demonstrates"
}
output "ecr_repository_url" {
  value       = module.ecr.repository_url
  description = "URL of the ECR repository the VS Code EC2 instance pushes the sample image to"
}
output "hpa_load_generator_command" {
  value       = module.hpa_demo.load_generator_command
  description = "Command that drives CPU load into the demo Service so the HorizontalPodAutoscaler, and then the cluster autoscaler, scale up"
}
output "kube_ops_view_service_command" {
  value       = module.kube_ops_view.describe_command
  description = "Command that shows the kube-ops-view Service, including EXTERNAL-IP - the NLB's DNS name - once the AWS Load Balancer Controller has reconciled it. The dashboard answers on http://<EXTERNAL-IP>:80. Terraform cannot output the address itself: the load balancer is created by the controller in response to the Service, not by a Terraform resource"
}
output "kube_ops_view_port_forward_command" {
  value       = module.kube_ops_view.port_forward_command
  description = "Command to reach the kube-ops-view dashboard on http://localhost:8080 without going through a load balancer, which is how to use it when kube_ops_view_service_type is ClusterIP. Built from the module's own output so the namespace, Service name and port cannot drift from what was applied (rules.md #5)"
}
