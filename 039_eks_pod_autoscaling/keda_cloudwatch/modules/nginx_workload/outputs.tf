output "name" {
  value       = var.name
  description = "Name of the Deployment, Service and Ingress"
}
output "namespace" {
  value       = var.namespace
  description = "Namespace the workload runs in, re-exposed so the caller does not restate it (rules.md B-5)"
}
output "stack_tag" {
  value       = local.stack_tag
  description = "The <namespace>/<name> value the controller writes into its ingress.k8s.aws/stack tag. A pre-created load balancer must carry exactly this to be adopted rather than duplicated, so it is derived here rather than by the caller (rules.md B-5/G-3)"
}
output "container_port" {
  value       = var.container_port
  description = "Port traffic arrives on. Exposed because with target-type ip the load balancer reaches this port on the pod directly, so a caller declaring the pod-side security group rule needs it (rules.md B-5)"
}
output "load_balancer_hostname_command" {
  value       = "kubectl -n ${var.namespace} get ingress ${var.name} -o jsonpath='{.status.loadBalancer.ingress[0].hostname}'"
  description = "Command reading the address the controller actually attached. Worth comparing against the pre-created load balancer's DNS name: if they differ, adoption failed and there are two load balancers (rules.md G-3)"
}
output "replicas_command" {
  value       = "kubectl -n ${var.namespace} get deployment ${var.name} -w"
  description = "Command watching the replica count the autoscaler drives. This Deployment's spec.replicas has two owners - this module sets the starting value, the ScaledObject moves it - so the field is excluded from the module's diff"
}
output "pods_command" {
  value       = "kubectl -n ${var.namespace} get pods -l app.kubernetes.io/name=${var.name} -o wide"
  description = "Command listing the workload's pods and the nodes they landed on, which is where added replicas become visible"
}
