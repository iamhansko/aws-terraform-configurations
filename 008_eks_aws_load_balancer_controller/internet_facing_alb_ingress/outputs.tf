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
output "alb_security_group_id" {
  value       = local.outputs.alb_security_group_id.value
  description = "ID of the ALB's frontend security group, handed to the controller through the Ingress annotation. This variant's ALB is internet-facing, so this group decides who can reach it"
}
output "game_namespace" {
  value       = local.outputs.game_namespace.value
  description = "Namespace holding the 2048 Deployment, Service and Ingress"
}
output "ingress_dns_name_command" {
  value       = local.outputs.ingress_dns_name_command.value
  description = "Command that shows the Ingress, whose ADDRESS column fills in once the controller has provisioned the ALB"
}
output "ingress_endpoint_command" {
  value       = local.outputs.ingress_endpoint_command.value
  description = "Command that prints the ALB's DNS name. The ALB is created by the AWS Load Balancer Controller rather than by Terraform, so its address is not a Terraform output"
}
output "ingress_fetch_command" {
  value       = local.outputs.ingress_fetch_command.value
  description = "Command that fetches the 2048 app through the ALB. This variant's ALB is internet-facing, so the same hostname also works from a browser"
}
output "node_group_name" {
  value       = local.outputs.node_group_name.value
  description = "Name of the managed node group hosting the controller and the 2048 pods"
}
output "update_kubeconfig_command" {
  value       = local.outputs.update_kubeconfig_command.value
  description = "Command that points kubectl on the VS Code instance at the cluster. User data already ran it; this is for recovering a lost kubeconfig"
}
