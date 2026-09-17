output "namespace" {
  value       = var.namespace
  description = "Namespace the workload runs in (rules.md B-5)"
}
output "service_name" {
  value       = var.service_name
  description = "Name of the Service"
}
output "ingress_name" {
  value       = var.create_ingress ? var.ingress_name : null
  description = "Name of the Ingress, or null when create_ingress is false"
}
output "ingress_stack_tag" {
  value       = var.create_ingress ? "${var.namespace}/${var.ingress_name}" : "${var.namespace}/${var.service_name}"
  description = "The <namespace>/<name> value the AWS Load Balancer Controller writes into its ingress.k8s.aws/stack (Ingress) or service.k8s.aws/stack (Service) tag. A pre-created load balancer must carry exactly this value to be adopted rather than duplicated, so it is derived here instead of being restated by the caller (rules.md B-5)"
}
output "describe_command" {
  value       = "kubectl -n ${var.namespace} get ${local.load_balancer_object}"
  description = "Command that shows the provisioned load balancer's DNS name once the controller has reconciled"
}
output "load_balancer_hostname_command" {
  value       = local.load_balancer_hostname_command
  description = "Command that prints just the load balancer's DNS name. The load balancer is created by the AWS Load Balancer Controller rather than by Terraform, so its address cannot be a Terraform output and has to be read from the cluster instead (rules.md H-2)"
}
output "load_balancer_fetch_command" {
  value       = "curl -s http://$(${local.load_balancer_hostname_command})"
  description = "Command that fetches the workload through the load balancer. Built from load_balancer_hostname_command so both reference one source of truth (rules.md B-5). For an internal load balancer this only succeeds from inside the VPC, which is what the bastion is for"
}
