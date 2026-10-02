output "stars_namespace" {
  value       = var.stars_namespace
  description = "Namespace holding the frontend and backend probes, re-exposed so callers do not restate it (rules.md B-5)"
}
output "client_namespace" {
  value       = var.client_namespace
  description = "Namespace holding the client probe"
}
output "management_ui_namespace" {
  value       = var.management_ui_namespace
  description = "Namespace holding the management UI"
}
output "management_ui_name" {
  value       = var.management_ui_name
  description = "Name of the management UI Service and Deployment"
}
output "stack_tag" {
  value       = "${var.management_ui_namespace}/${var.management_ui_name}"
  description = "The <namespace>/<name> value the AWS Load Balancer Controller writes into the service.k8s.aws/stack tag for this Service. A pre-created load balancer must carry exactly this to be adopted rather than duplicated, so it is derived here from the names this module owns instead of being restated by the caller (rules.md B-5/G-3)"
}
output "management_ui_container_port" {
  value       = var.management_ui_container_port
  description = "Container port the management UI listens on. With target-type ip the load balancer sends traffic here rather than to the Service port, so this is the port the pod-side security group rule has to open (rules.md G-1/G-2)"
}
output "management_ui_service_port" {
  value       = var.management_ui_service_port
  description = "Port the Service publishes, and therefore the load balancer's listener port - the one the frontend security group has to open"
}
output "load_balancer_hostname_command" {
  value       = "kubectl -n ${var.management_ui_namespace} get service ${var.management_ui_name} -o jsonpath='{.status.loadBalancer.ingress[0].hostname}'"
  description = "Command reading the address the controller actually attached. Worth comparing against the pre-created load balancer's DNS name: if they differ, adoption failed and there are now two load balancers (rules.md G-3)"
}
output "graph_check_command" {
  value       = "kubectl -n ${var.management_ui_namespace} rollout status deployment ${var.management_ui_name} && kubectl -n ${var.stars_namespace} get pods -o wide && kubectl -n ${var.client_namespace} get pods -o wide"
  description = "Command confirming the UI is up and every probe is running. All of them have to be Running before the graph shows anything, and a probe still pulling its image looks the same as one being denied"
}
output "network_policies_applied" {
  value       = var.apply_network_policies
  description = "Whether the demo's NetworkPolicy objects were created, re-exposed from the input so the graph's expected shape is visible in terraform output (rules.md B-5). True means the finished state: UI to every probe, frontend to backend, client to frontend, nothing else"
}
output "network_policy_names" {
  value = var.apply_network_policies ? concat(
    [for key, namespace in local.default_deny_namespaces : "${namespace}/default-deny"],
    [
      "${var.stars_namespace}/allow-ui",
      "${var.client_namespace}/allow-ui",
      "${var.stars_namespace}/backend-policy",
      "${var.stars_namespace}/frontend-policy",
    ],
  ) : []
  description = "The <namespace>/<name> of every policy this module created, so what should be in force can be compared against 'kubectl get networkpolicy -A' without reading the module"
}
output "policy_list_command" {
  value       = "kubectl get networkpolicy -A"
  description = "Command listing every NetworkPolicy in force. If the graph does not match what these say, the enforcement switch on the vpc-cni addon is the thing to check before the policies themselves (rules.md E-5)"
}
output "policy_describe_command" {
  value       = "kubectl -n ${var.stars_namespace} describe networkpolicy"
  description = "Command showing which pods each policy in the stars namespace selects and what it allows. Policies are additive, so a pod's effective rules are the union of every policy selecting it - which is why default-deny and allow-ui coexist rather than one replacing the other"
}
