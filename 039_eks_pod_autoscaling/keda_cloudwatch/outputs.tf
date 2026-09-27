# Every output is a projection of local.outputs in main.tf, which is also what the
# README written onto the VS Code instance is rendered from (rules.md H-2). No value
# expression is written here: an output that built its own value would be missing
# from that README, and nothing would fail to say so - the apply would succeed either
# way. Whether the pattern still holds is checked by counting: the number of output
# blocks here must equal the number of entries in local.outputs.
#
# description is the one thing repeated, because Terraform rejects an expression
# there ("Variables not allowed") - it has to be a literal.
output "vscode_url" {
  value       = local.outputs.vscode_url.value
  description = "URL to access the code-server web UI on the VS Code EC2 instance"
}
output "cluster_name" {
  value       = local.outputs.cluster_name.value
  description = "Name of the EKS cluster"
}
output "cluster_endpoint" {
  value       = local.outputs.cluster_endpoint.value
  description = "API server endpoint of the EKS cluster"
}
output "application_url" {
  value       = local.outputs.application_url.value
  description = "HTTP URL of the pre-created ALB the controller adopts, known from state at apply time (rules.md G-3)"
}
output "keda_release" {
  value       = local.outputs.keda_release.value
  description = "The KEDA release, its pinned chart version and the IAM role its operator assumes to read CloudWatch"
}
output "scaler_target" {
  value       = local.outputs.scaler_target.value
  description = "Requests per period each replica is expected to absorb, and the replica range KEDA may use"
}
output "scaler_expression" {
  value       = local.outputs.scaler_expression.value
  description = "The CloudWatch Metrics Insights query the scaler runs against the load balancer's request count"
}
output "adoption_stack_tag" {
  value       = local.outputs.adoption_stack_tag.value
  description = "The <namespace>/<name> stack tag the pre-created ALB carries, which is what the controller matches to adopt it rather than build a second one (rules.md G-3)"
}
output "load_balancer_count_command" {
  value       = local.outputs.load_balancer_count_command.value
  description = "Command listing the controller-owned load balancers. Two results means adoption failed, which is not reported as an error (rules.md G-3)"
}
output "scaled_object_command" {
  value       = local.outputs.scaled_object_command.value
  description = "Command showing whether KEDA accepted the ScaledObject and authenticated"
}
output "metric_value_command" {
  value       = local.outputs.metric_value_command.value
  description = "Command reading the external metric value KEDA publishes from the CloudWatch query"
}
output "hpa_command" {
  value       = local.outputs.hpa_command.value
  description = "Command watching the HorizontalPodAutoscaler KEDA creates from the ScaledObject"
}
output "load_generator_command" {
  value       = local.outputs.load_generator_command.value
  description = "Command creating a load generator pod that requests the ALB, which is the only path the scaler's metric can see"
}
output "pods_command" {
  value       = local.outputs.pods_command.value
  description = "Command listing the workload's pods and the nodes they landed on"
}
output "keda_operator_logs_command" {
  value       = local.outputs.keda_operator_logs_command.value
  description = "Command following the KEDA operator's log, where scaler authentication and metric queries are explained"
}
output "update_kubeconfig_command" {
  value       = local.outputs.update_kubeconfig_command.value
  description = "Command that points kubectl on the VS Code instance at the cluster"
}
