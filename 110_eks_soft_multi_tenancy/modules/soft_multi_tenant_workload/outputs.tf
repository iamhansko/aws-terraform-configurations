output "tenant_namespaces" {
  value       = var.tenants
  description = "The namespaces created, by tenant label. Re-exposed so the caller can compare them against the namespaces the tenant roles are scoped to - a role scoped to a namespace that does not exist grants nothing and reports nothing (rules.md B-5)"
}
output "management_ui_namespace" {
  value       = var.management_ui_namespace
  description = "Namespace the management UI runs in"
}
output "management_ui_name" {
  value       = var.management_ui_name
  description = "Name of the management UI Service and Deployment"
}
output "stack_tag" {
  value       = "${var.management_ui_namespace}/${var.management_ui_name}"
  description = "The <namespace>/<name> value the AWS Load Balancer Controller writes into its service.k8s.aws/stack tag. A pre-created load balancer must carry exactly this to be adopted rather than duplicated, so it is derived here rather than restated by the caller (rules.md B-5/G-3)"
}
output "management_ui_service_port" {
  value       = var.management_ui_service_port
  description = "Port the Service publishes, and therefore the load balancer's listener port - what the frontend security group has to open (rules.md B-5)"
}
output "management_ui_container_port" {
  value       = var.management_ui_container_port
  description = "Port the collector listens on. With nlb-target-type ip the load balancer sends traffic straight to the pod, so this - not the Service port - is what a pod-side security group rule has to open (rules.md G-1/G-2)"
}
output "network_policies_applied" {
  value       = var.apply_network_policies
  description = "Whether the isolating policies exist. False produces a fully connected graph - which is also what applying them to a CNI that does not enforce them looks like, so this is worth reading alongside the addon's network_policy_enabled (rules.md B-5)"
}
output "policy_names" {
  value = var.apply_network_policies ? sort(flatten([
    for label, namespace in var.tenants : [
      "${namespace}/default-deny",
      "${namespace}/allow-ui",
      "${namespace}/backend-policy",
    ]
  ])) : []
  description = "Every policy this module created, by namespace and name. Three per tenant, and the order they are listed in is the order they matter: deny everything, then let the UI in, then let the frontend reach the backend"
}
output "probe_urls" {
  value = {
    for label, namespace in var.tenants : label => {
      frontend = "http://frontend.${namespace}.svc.cluster.local:${var.frontend_port}/status"
      backend  = "http://backend.${namespace}.svc.cluster.local:${var.backend_port}/status"
    }
  }
  description = "What each probe answers on. Every probe is told to poll every tenant's services, which is what makes a blocked path appear as a timeout in the graph rather than having to be inferred"
}
output "load_balancer_hostname_command" {
  value       = "kubectl -n ${var.management_ui_namespace} get service ${var.management_ui_name} -o jsonpath='{.status.loadBalancer.ingress[0].hostname}'"
  description = "The address the controller actually attached. Compare it against a pre-created load balancer's DNS name: if they differ, the controller built its own instead of adopting (rules.md G-3)"
}
output "quota_command" {
  value       = "kubectl get resourcequota,limitrange -A -l '!kubernetes.io/metadata.name' -o wide"
  description = "The quotas and limit ranges in effect. The limit range is what makes the quota real - a container with no requests counts as zero against a requests quota, so without defaults a tenant can exceed what the quota appears to allow"
}
output "policy_list_command" {
  value       = "kubectl get networkpolicies -A"
  description = "Every policy the API server holds. Note that this says nothing about enforcement: the API server accepts NetworkPolicy objects whether or not the CNI implements them (rules.md E-5)"
}
output "cross_tenant_test_commands" {
  value = {
    for label, namespace in var.tenants : label => join("\n", concat(
      ["# from ${label}'s frontend, expected: its own backend answers, every other tenant's times out"],
      ["FRONTEND=$(kubectl get pod -n ${namespace} -l role=frontend -o jsonpath='{.items[0].metadata.name}')"],
      [for other_label, other_namespace in var.tenants :
        "kubectl exec -n ${namespace} $FRONTEND -- wget -q -T 5 -O - http://backend.${other_namespace}.svc.cluster.local:${var.backend_port}/status && echo '  ^ reached ${other_label}' || echo '  ^ blocked to ${other_label}'"
      ],
    ))
  }
  description = "The test, per tenant. A tenant reaching its own backend and timing out on the others is the policies working; reaching all of them means either the policies are off or the CNI is not enforcing them"
}
