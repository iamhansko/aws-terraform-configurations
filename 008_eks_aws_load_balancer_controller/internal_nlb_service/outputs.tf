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
output "nlb_security_group_id" {
  value       = local.outputs.nlb_security_group_id.value
  description = "ID of the NLB's frontend security group, handed to the controller through the Service annotation"
}
output "service_dns_name_command" {
  value       = local.outputs.service_dns_name_command.value
  description = "Command that shows the Service, whose EXTERNAL-IP column fills in once the controller has provisioned the NLB"
}
output "service_endpoint_command" {
  value       = local.outputs.service_endpoint_command.value
  description = "Command that prints the NLB's DNS name. The NLB is created by the AWS Load Balancer Controller rather than by Terraform, so its address is not a Terraform output"
}
output "service_fetch_command" {
  value       = local.outputs.service_fetch_command.value
  description = "Command that fetches the dashboard through the NLB. The NLB is internal, so this only succeeds from inside the VPC - run it on the VS Code instance"
}
output "service_port_forward_command" {
  value       = local.outputs.service_port_forward_command.value
  description = "Command that reaches the dashboard on localhost without going through the NLB at all"
}
output "update_kubeconfig_command" {
  value       = local.outputs.update_kubeconfig_command.value
  description = "Command that points kubectl on the VS Code instance at the cluster. User data already ran it; this is for recovering a lost kubeconfig"
}
