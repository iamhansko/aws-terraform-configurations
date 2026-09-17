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
  description = "ID of the ALB's frontend security group, handed to the controller through the Ingress annotation"
}
output "synced_load_balancer_url" {
  value       = local.outputs.synced_load_balancer_url.value
  description = "HTTP URL of the pre-created load balancer, available straight from Terraform state rather than only from 'kubectl get ingress'"
}
output "synced_load_balancer_name" {
  value       = local.outputs.synced_load_balancer_name.value
  description = "Name of the load balancer Terraform pre-created for the controller to adopt"
}
output "synced_load_balancer_arn" {
  value       = local.outputs.synced_load_balancer_arn.value
  description = "ARN of the pre-created load balancer. Knowing this before the controller has reconciled anything is the practical benefit of the sync approach"
}
output "synced_load_balancer_stack_tag" {
  value       = local.outputs.synced_load_balancer_stack_tag.value
  description = "The <namespace>/<name> stack tag the load balancer carries. The controller adopts the load balancer only when this matches the Ingress or Service it is reconciling"
}
output "ingress_dns_name_command" {
  value       = local.outputs.ingress_dns_name_command.value
  description = "Command that shows the Ingress. Its ADDRESS should be the pre-created load balancer, not a new one"
}
output "ingress_endpoint_command" {
  value       = local.outputs.ingress_endpoint_command.value
  description = "Command that prints the DNS name the controller actually attached to the Ingress, for comparing against synced_load_balancer_url"
}
output "ingress_fetch_command" {
  value       = local.outputs.ingress_fetch_command.value
  description = "Command that fetches the 2048 app through the ALB. For an internal load balancer this only succeeds from inside the VPC"
}
output "update_kubeconfig_command" {
  value       = local.outputs.update_kubeconfig_command.value
  description = "Command that points kubectl on the VS Code instance at the cluster. User data already ran it; this is for recovering a lost kubeconfig"
}
