output "name" {
  value       = var.name
  description = "Name of the Deployment, re-exposed so callers do not restate it (rules.md B-5)"
}

output "namespace" {
  value       = var.namespace
  description = "Namespace the workload lives in"
}

output "pod_role_arn" {
  value       = aws_iam_role.mcp_server.arn
  description = "ARN of the role the pod assumes through Pod Identity. The caller needs it to create the cluster access entry that decides what the MCP server may do inside Kubernetes"
}

output "pod_role_name" {
  value       = aws_iam_role.mcp_server.name
  description = "Name of the pod's IAM role, for a caller that has to attach another policy to it"
}

output "service_account_name" {
  value       = var.service_account_name
  description = "Service account the pod runs as, re-exposed so a caller's verification command does not restate it (rules.md B-5)"
}

output "stack_tag" {
  value       = var.stack_tag
  description = "The <namespace>/<name> value the AWS Load Balancer Controller writes into its ingress.k8s.aws/stack tag, re-exposed so a mismatch with the pre-created load balancer is visible in terraform output (rules.md B-5/G-3)"
}

output "deployment_status_command" {
  value       = "kubectl -n ${var.namespace} get deployment ${var.name} -o wide"
  description = "Command that shows the Deployment. A pod in ImagePullBackOff means the CodeBuild build never pushed the image"
}

output "pod_log_command" {
  value       = "kubectl -n ${var.namespace} logs deploy/${var.name} --tail 100"
  description = "Command that reads the proxy's log, which is where an AWS access denied from the MCP server appears"
}

output "ingress_status_command" {
  value       = "kubectl -n ${var.namespace} get ingress ${var.ingress_name}"
  description = "Command that shows the Ingress and its address. An empty ADDRESS with a class set points at the controller log"
}

output "load_balancer_hostname_command" {
  value       = "kubectl -n ${var.namespace} get ingress ${var.ingress_name} -o jsonpath='{.status.loadBalancer.ingress[0].hostname}' ; echo"
  description = "Command that reads the load balancer address the controller attached. Compare it against the pre-created load balancer's DNS name: two different names mean the adoption tags did not match and a second one was built (rules.md G-3)"
}
