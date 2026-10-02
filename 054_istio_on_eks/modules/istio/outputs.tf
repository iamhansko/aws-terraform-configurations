output "chart_version" {
  value       = var.chart_version
  description = "Version all three charts were installed at, re-exposed so the mesh version is visible in terraform output rather than only inside a release (rules.md B-5)"
}
output "control_plane_namespace" {
  value       = var.control_plane_namespace
  description = "Namespace istiod runs in, re-exposed so callers that add resources alongside it read one value (rules.md B-5)"
}
output "gateway_namespace" {
  value       = var.gateway_namespace
  description = "Namespace the ingress gateway runs in"
}
output "gateway_name" {
  value       = var.gateway_release_name
  description = "Name of the gateway release, and therefore of the Service the chart creates"
}
output "gateway_stack_tag" {
  value       = "${var.gateway_namespace}/${var.gateway_release_name}"
  description = "The <namespace>/<name> value the AWS Load Balancer Controller writes into its service.k8s.aws/stack tag for this Service. A pre-created load balancer must carry exactly this to be adopted rather than duplicated, so it is derived here instead of being restated by the caller (rules.md B-5/G-3)"
}
output "gateway_selector" {
  value       = { istio = "ingressgateway" }
  description = "The label selector a Gateway resource must use to bind to this gateway's proxy. The chart applies istio: ingressgateway to the Deployment's pods, and a Gateway whose selector matches nothing is accepted by the API server and configures no listener - so the load balancer has healthy targets and every request is refused (rules.md B-5)"
}
output "service_ports" {
  value       = var.service_ports
  description = "Ports the gateway Service publishes, re-exposed so the frontend security group opens exactly the ports that became listeners (rules.md B-5/G-1)"
}
output "health_check_port" {
  value       = var.health_check_port
  description = "Port the load balancer health-checks on the pod. The pod-side security group rule has to admit this as well as the traffic ports, or every target stays unhealthy while the listener and the rules all look correct (rules.md G-2)"
}
output "gateway_hostname_command" {
  value       = "kubectl -n ${var.gateway_namespace} get service ${var.gateway_release_name} -o jsonpath='{.status.loadBalancer.ingress[0].hostname}'"
  description = "The address the controller actually attached to the gateway Service. Compare it against the pre-created load balancer's URL: the same value means the pre-created one was adopted, a different value means a second load balancer was built instead (rules.md G-3)"
}
output "proxy_status_command" {
  value       = "kubectl -n ${var.gateway_namespace} exec deploy/${var.gateway_release_name} -c istio-proxy -- pilot-agent request GET listeners"
  description = "The listeners istiod has actually programmed into the gateway proxy. Empty output with a Running pod means no Gateway resource binds a port, which is the state in which the load balancer is healthy and every request is still refused"
}
