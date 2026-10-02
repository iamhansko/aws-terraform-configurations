# Every value here is a projection of local.outputs in main.tf. No output declares its
# own value expression: the same map is what the README on the VS Code instance is
# rendered from, so an output written directly here would be missing from that README and
# nothing would report it - the apply succeeds either way (rules.md H-2).
#
# description is the one exception. Terraform does not allow an expression there
# ("Variables not allowed"), so the wording exists as a literal in both places while the
# value still exists in only one.
output "vscode_url" {
  value       = local.outputs.vscode_url.value
  description = "Open the IDE here. The kubectl commands below are meant to be run from its terminal"
}
output "cluster_name" {
  value       = local.outputs.cluster_name.value
  description = "Name of the EKS cluster, which the controller also writes into the elbv2.k8s.aws/cluster tag on load balancers it owns"
}
output "cluster_endpoint" {
  value       = local.outputs.cluster_endpoint.value
  description = "API server endpoint. Public so the helm and kubectl providers could reach it during apply - narrow public_access_cidrs to your own address"
}
output "istio_version" {
  value       = local.outputs.istio_version.value
  description = "Version all three Istio charts were installed at, pinned rather than whatever the repository serves today"
}
output "gateway_url" {
  value       = local.outputs.gateway_url.value
  description = "The mesh's front door, serving the demo application. Known from state because Terraform created the network load balancer and the controller adopted it (rules.md G-3)"
}
output "kiali_url" {
  value       = local.outputs.kiali_url.value
  description = "The mesh console, with no login. Its graph needs a metrics source this project does not install; its Services, Workloads and Istio Config pages work immediately"
}
output "gateway_stack_tag" {
  value       = local.outputs.gateway_stack_tag.value
  description = "The <namespace>/<name> the NLB carries in service.k8s.aws/stack. A mismatch with the gateway Service makes the controller build a second load balancer rather than adopt this one (rules.md G-3)"
}
output "kiali_stack_tag" {
  value       = local.outputs.kiali_stack_tag.value
  description = "The same for the ALB, under ingress.k8s.aws/stack because it comes from an Ingress. The two prefixes are not interchangeable (rules.md G-3)"
}
output "sidecar_check_command" {
  value       = local.outputs.sidecar_check_command.value
  description = "Lists each demo pod's containers. Two names means sidecar injection worked; one means the pod is not in the mesh and nothing reports it"
}
output "routing_check_command" {
  value       = local.outputs.routing_check_command.value
  description = "The Gateway and VirtualService that decide whether the gateway URL serves anything"
}
output "proxy_listener_command" {
  value       = local.outputs.proxy_listener_command.value
  description = "Asks the gateway proxy what it is listening on, which separates a misconfigured load balancer from a mesh with no routes"
}
output "adopted_load_balancer_check_command" {
  value       = local.outputs.adopted_load_balancer_check_command.value
  description = "Lists every load balancer tagged for this cluster. Two is correct; more means a pre-created one was not adopted (rules.md G-3)"
}
output "gateway_hostname_command" {
  value       = local.outputs.gateway_hostname_command.value
  description = "The address the controller attached to the gateway Service, for comparison against gateway_url"
}
output "kiali_hostname_command" {
  value       = local.outputs.kiali_hostname_command.value
  description = "The address the controller attached to the Kiali Ingress, for comparison against kiali_url"
}
output "kiali_status_command" {
  value       = local.outputs.kiali_status_command.value
  description = "What the operator made of the Kiali CR, then whether the server it built is up"
}
output "traffic_generator_command" {
  value       = local.outputs.traffic_generator_command.value
  description = "Sends requests through the mesh from inside it, so the sidecars have something to report"
}
output "disable_routing_command" {
  value       = local.outputs.disable_routing_command.value
  description = "Removes the Gateway and VirtualService through Terraform, reaching the state where the load balancer is healthy and every request is refused (rules.md B-4)"
}
output "update_kubeconfig_command" {
  value       = local.outputs.update_kubeconfig_command.value
  description = "Re-points kubectl on the instance at the cluster. User data already ran this"
}
