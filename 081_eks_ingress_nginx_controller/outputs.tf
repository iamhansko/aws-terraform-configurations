# Every value here is a projection of local.outputs in main.tf, which the README written onto
# the VS Code instance renders from the same map - so no value expression exists twice, and an
# output cannot be added without also appearing in that README (rules.md B-5/H-2).
#
# description is the one thing that cannot be projected: Terraform rejects an expression in an
# output's description ("Variables not allowed"), so the wording is a literal on both sides.
output "vscode_url" {
  value       = local.outputs.vscode_url.value
  description = "Open the IDE here. The kubectl commands below are meant to be run from its terminal"
}
output "cluster_name" {
  value       = local.outputs.cluster_name.value
  description = "Name of the EKS cluster, which the AWS Load Balancer Controller also writes into the tag it finds its own load balancers by"
}
output "cluster_endpoint" {
  value       = local.outputs.cluster_endpoint.value
  description = "API server endpoint. Public, unlike the _monolithic template's private one, so the helm and kubectl providers could reach it during apply"
}
output "ingress_classes" {
  value       = local.outputs.ingress_classes.value
  description = "One ingress-nginx release per class, each with its own controllerValue and its own controller Service"
}
output "load_balancer_urls" {
  value       = local.outputs.load_balancer_urls.value
  description = "One pre-created, controller-adopted NLB per class, with its address known from state (rules.md G-3)"
}
output "app_url" {
  value       = local.outputs.app_url.value
  description = "The demo app through the class its Ingress currently names"
}
output "adopted_load_balancer_check_command" {
  value       = local.outputs.adopted_load_balancer_check_command.value
  description = "1. Lists every load balancer tagged for this cluster. Two is correct; four means adoption failed silently"
}
output "ingress_class_list_command" {
  value       = local.outputs.ingress_class_list_command.value
  description = "2. The IngressClasses the cluster has, with their controller values and whether any claims to be default"
}
output "workload_rollout_command" {
  value       = local.outputs.workload_rollout_command.value
  description = "3. Waits for the demo pod, which is slow on first start because MySQL initialises its data directory"
}
output "claim_status_command" {
  value       = local.outputs.claim_status_command.value
  description = "4. Whether the EBS volume behind the demo's claim was provisioned"
}
output "ingress_status_command" {
  value       = local.outputs.ingress_status_command.value
  description = "5. The Ingress, its class, and the address its controller attached"
}
output "switch_class_command" {
  value       = local.outputs.switch_class_command.value
  description = "6. Moves the app to the other class, which is the demo - only the class name changes"
}
output "other_class_check_command" {
  value       = local.outputs.other_class_check_command.value
  description = "7. Confirms the class the Ingress does not name serves nginx's default backend rather than the app"
}
output "controller_logs_command" {
  value       = local.outputs.controller_logs_command.value
  description = "8. The log of the controller that owns the class the Ingress names"
}
output "update_kubeconfig_command" {
  value       = local.outputs.update_kubeconfig_command.value
  description = "Re-points kubectl at the cluster. User data already ran this"
}
