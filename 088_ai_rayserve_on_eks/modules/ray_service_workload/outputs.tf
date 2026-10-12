output "name" {
  value       = var.name
  description = "Name of the RayService, re-exposed so callers do not restate it (rules.md B-5)"
}

output "namespace" {
  value       = var.namespace
  description = "Namespace the workload lives in"
}

output "head_service_name" {
  value       = "${var.name}-head-svc"
  description = "Name of the head Service the KubeRay operator creates, which is the Ingress backend. Derived here rather than by the caller, because the naming convention belongs to the operator"
}

output "ray_service_status_command" {
  value       = "kubectl -n ${var.namespace} get rayservice ${var.name} -o wide"
  description = "Command that shows whether the Serve application reached RUNNING. DEPLOY_FAILED with the cluster healthy is a Serve config problem - the operator log says which key"
}

output "ray_pods_command" {
  value       = "kubectl -n ${var.namespace} get pods -o wide"
  description = "Command that shows the head and worker pods and the nodes they landed on. A worker Pending with GPU nodes present usually means the device plugin is not advertising nvidia.com/gpu yet, or the toleration does not match the pool's taint"
}

output "serve_applications_command" {
  value       = "kubectl -n ${var.namespace} get rayservice ${var.name} -o jsonpath='{.status.activeServiceStatus.applications}' ; echo"
  description = "Command that prints the per-application Serve status, which is where a replica stuck loading the model shows up"
}

output "ingress_status_command" {
  value       = var.create_ingress ? "kubectl -n ${var.namespace} get ingress ${var.ingress_name}" : "echo 'no Ingress: create_ingress is false'"
  description = "Command that shows the Ingress and its address. An empty ADDRESS with an empty CLASS means no controller claimed it; an empty ADDRESS with a class set points at the controller log"
}

output "load_balancer_hostname_command" {
  value       = var.create_ingress ? "kubectl -n ${var.namespace} get ingress ${var.ingress_name} -o jsonpath='{.status.loadBalancer.ingress[0].hostname}' ; echo" : "echo 'no Ingress: create_ingress is false'"
  description = "Command that reads the ALB address the controller attached. The load balancer is not a Terraform resource here, so this is the only place the address exists (rules.md G-1)"
}
