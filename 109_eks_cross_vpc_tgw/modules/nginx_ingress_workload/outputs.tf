output "name" {
  value       = var.name
  description = "Name of the Deployment, re-exposed so callers do not restate it (rules.md B-5)"
}

output "namespace" {
  value       = var.namespace
  description = "Namespace the Deployment lives in"
}

output "replicas" {
  value       = var.replicas
  description = "Replica count asked for, which is what a Pending pod count is measured against"
}

output "deployment_status_command" {
  value       = "kubectl -n ${var.namespace} get deployment ${var.name} -o wide"
  description = "Command that shows how many of the requested replicas are ready"
}

output "stack_tag" {
  value       = "${var.namespace}/${var.name}"
  description = "The <namespace>/<name> value the AWS Load Balancer Controller writes into its ingress.k8s.aws/stack tag. A pre-created load balancer has to carry exactly this to be adopted instead of duplicated (rules.md B-5/G-3)"
}

output "ingress_status_command" {
  value       = "kubectl -n ${var.namespace} get ingress ${var.name}"
  description = "Command that shows the Ingress and its address. An empty ADDRESS with a class set points at the controller log; an empty CLASS means no controller claimed it"
}

output "load_balancer_hostname_command" {
  value       = "kubectl -n ${var.namespace} get ingress ${var.name} -o jsonpath='{.status.loadBalancer.ingress[0].hostname}' ; echo"
  description = "Command that reads the load balancer address the controller attached. Compare it against the pre-created load balancer's DNS name: two different names mean the adoption tags did not match (rules.md G-3)"
}

output "pod_ips_command" {
  value       = "kubectl -n ${var.namespace} get pods -l app=${var.name} -o custom-columns=NAME:.metadata.name,IP:.status.podIP,NODE:.spec.nodeName"
  description = "Command that prints each pod's address. These come out of the non-routable secondary CIDR, which is the point of this project - and why traffic leaving for the other VPC has to be translated first"
}

output "curl_command" {
  value       = "kubectl -n ${var.namespace} exec deploy/${var.name} -- curl -sS -o /dev/null -w '%%{http_code}\\n'"
  description = "Prefix for a request made from inside a pod in this cluster. Append the other cluster's ALB address to it: that request leaves a non-routable pod address, is translated by the private NAT gateway, crosses the transit gateway and comes back - which is the whole demonstration"
}
