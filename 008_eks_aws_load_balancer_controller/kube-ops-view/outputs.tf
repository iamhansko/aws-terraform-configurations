# Every output is a projection of local.outputs in main.tf, which is also what
# the README written onto the VS Code instance is rendered from (rules.md H-2).
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
output "load_balancer_controller_role_arn" {
  value       = local.outputs.load_balancer_controller_role_arn.value
  description = "ARN of the IAM role the AWS Load Balancer Controller assumes through IRSA"
}
output "kube_ops_view_namespace" {
  value       = local.outputs.kube_ops_view_namespace.value
  description = "Namespace the kube-ops-view dashboard runs in"
}
output "nlb_security_group_id" {
  value       = local.outputs.nlb_security_group_id.value
  description = "ID of the frontend security group attached to the NLB. The only group on it, because this variant disables the shared backend security group"
}
output "load_balancer_security_groups_command" {
  value       = local.outputs.load_balancer_security_groups_command.value
  description = "Command listing the security groups actually attached to the NLB, for confirming no shared backend group was created"
}
output "pod_ingress_rule_command" {
  value       = local.outputs.pod_ingress_rule_command.value
  description = "Command showing the Terraform-declared cluster security group rule that lets the NLB reach the pods, which the controller no longer writes"
}
output "kube_ops_view_service_type" {
  value       = local.outputs.kube_ops_view_service_type.value
  description = "Service type applied to the dashboard, which decides whether a load balancer exists at all"
}
output "kube_ops_view_service_command" {
  value       = local.outputs.kube_ops_view_service_command.value
  description = "Command that shows the dashboard's Service, including the load balancer address when the type is LoadBalancer"
}
output "kube_ops_view_port_forward_command" {
  value       = local.outputs.kube_ops_view_port_forward_command.value
  description = "Command to reach the dashboard on http://localhost:8080 without publishing it, which is how to use the ClusterIP default"
}
output "kube_ops_view_endpoint_command" {
  value       = local.outputs.kube_ops_view_endpoint_command.value
  description = "Command that prints the load balancer's DNS name, or null when the Service type is not LoadBalancer"
}
output "kube_ops_view_fetch_command" {
  value       = local.outputs.kube_ops_view_fetch_command.value
  description = "Command that fetches the dashboard through the load balancer, or null when the Service type is not LoadBalancer"
}
output "update_kubeconfig_command" {
  value       = local.outputs.update_kubeconfig_command.value
  description = "Command that points kubectl on the VS Code instance at the cluster. User data already ran it; this is for recovering a lost kubeconfig"
}
