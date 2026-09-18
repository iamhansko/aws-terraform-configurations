# Every output is a projection of local.outputs in main.tf, which is also what
# the README written onto the VS Code instance is rendered from (rules.md H-2).
# No value expression is written here: an output that built its own value would
# be missing from that README, and nothing would fail to tell anyone - the apply
# would succeed either way. Whether this pattern still holds is checked by
# counting: the number of output blocks here must equal the number of entries in
# local.outputs.
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
  description = "API server endpoint of the EKS cluster. Public so the kubectl provider can reach it during apply"
}
output "app_fargate_profile_name" {
  value       = local.outputs.app_fargate_profile_name.value
  description = "Name of the Fargate profile selecting the workload namespace"
}
output "opensearch_dashboard_url" {
  value       = local.outputs.opensearch_dashboard_url.value
  description = "OpenSearch Dashboards URL. Log in with the master user, which is a domain-internal credential rather than IAM"
}
output "opensearch_log_writer_role_name" {
  value       = local.outputs.opensearch_log_writer_role_name.value
  description = "Name of the OpenSearch security role the Fargate pod execution role is mapped onto for fine-grained access control"
}
output "logging_configmap_command" {
  value       = local.outputs.logging_configmap_command.value
  description = "Command printing the rendered Fluent Bit configuration as the cluster has it"
}
output "namespace_label_command" {
  value       = local.outputs.namespace_label_command.value
  description = "Command confirming the aws-observability: enabled label that switches the log router on"
}
output "pods_check_command" {
  value       = local.outputs.pods_check_command.value
  description = "Command listing the demo pods and the Fargate node each one landed on"
}
output "stress_log_command" {
  value       = local.outputs.stress_log_command.value
  description = "Command showing the status codes the stress pod gets back from the web pod through its Service"
}
output "index_check_command" {
  value       = local.outputs.index_check_command.value
  description = "Command listing the domain's indices, which is how to tell whether Fluent Bit has written anything"
}
output "roles_mapping_check_command" {
  value       = local.outputs.roles_mapping_check_command.value
  description = "Command showing the fine-grained access control mapping as the domain holds it. The Fargate pod execution role ARN has to appear in backend_roles, or every write is rejected with 403"
}
output "fluentbit_process_log_command" {
  value       = local.outputs.fluentbit_process_log_command.value
  description = "Command listing the CloudWatch log groups that may hold Fluent Bit's own process log, which is where a rejected write is reported"
}
output "demo_cleanup_command" {
  value       = local.outputs.demo_cleanup_command.value
  description = "Command stopping the demo workload by setting create_demo_workload to false. The pods are Terraform resources, so deleting them with kubectl gets them recreated on the next apply"
}
output "update_kubeconfig_command" {
  value       = local.outputs.update_kubeconfig_command.value
  description = "Command that points kubectl on the VS Code instance at the cluster. User data already ran it; this is for recovering a lost kubeconfig"
}
