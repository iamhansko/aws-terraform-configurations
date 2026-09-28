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
  description = "Name of the EKS cluster"
}
output "cluster_endpoint" {
  value       = local.outputs.cluster_endpoint.value
  description = "API server endpoint. Public so the helm and kubectl providers could reach it during apply - narrow public_access_cidrs to your own address"
}
output "trace_service" {
  value       = local.outputs.trace_service.value
  description = "The service namespace and name the sample application labels its traces with. These are OpenTelemetry resource attributes rather than Kubernetes namespaces, and they are what the node in the X-Ray service map is called"
}
output "otlp_endpoint" {
  value       = local.outputs.otlp_endpoint.value
  description = "Where an instrumented application sends traces. This collector is a Deployment behind a Service, not a DaemonSet - nothing is scraped, applications send to it, which is why a workload has to be pointed here"
}
output "addon_configuration" {
  value       = local.outputs.addon_configuration.value
  description = "The JSON the adot add-on received. Read it first when no traces arrive: a key in the wrong place is valid JSON the add-on ignores, and nothing anywhere reports that (rules.md E-5)"
}
output "collector_role" {
  value       = local.outputs.collector_role.value
  description = "The IRSA role the OTLP collector assumes to put trace segments. Its trust policy names the service account the add-on creates - a name this configuration cannot choose, so a mismatch shows up as an exporter that cannot authenticate rather than as anything Terraform reports"
}
output "sample_app_role" {
  value       = local.outputs.sample_app_role.value
  description = "The role the application assumes for its /aws-sdk-call endpoint, which lists S3 buckets. Scoped to s3:ListAllMyBuckets, where the _monolithic template attached AmazonS3FullAccess - read, write and delete on every bucket in the account - to satisfy that one call"
}
output "permission_check_command" {
  value       = local.outputs.permission_check_command.value
  description = "The RBAC that lets the eks:addon-manager user create the operator. If the add-on reports a create failure, the message names the object it could not create and every one of them is covered here"
}
output "collector_status_command" {
  value       = local.outputs.collector_status_command.value
  description = "An OpenTelemetryCollector with no matching Deployment means the operator has not reconciled it, which is almost always its webhook failing to serve - check cert-manager before anything else"
}
output "cert_manager_command" {
  value       = local.outputs.cert_manager_command.value
  description = "The operator's webhook certificate comes from here. cert-manager not being ready is the single most common reason this project appears to install cleanly and collect nothing"
}
output "rollout_status_command" {
  value       = local.outputs.rollout_status_command.value
  description = "It is a JVM, so it takes the longer of the two Deployments. Until it is up the traffic generator's requests fail and no traces are produced at all"
}
output "manual_call_command" {
  value       = local.outputs.manual_call_command.value
  description = "The fastest way to get something to look for. This endpoint is the one that uses the IRSA role, so a failure here is a permissions problem rather than a tracing one"
}
output "sample_app_log_command" {
  value       = local.outputs.sample_app_log_command.value
  description = "Where a wrong OTLP endpoint appears. The application stays running and healthy while every export fails here, and nothing else reports it"
}
output "collector_log_command" {
  value       = local.outputs.collector_log_command.value
  description = "Where an AccessDenied from X-Ray appears. The collector stays Running either way, so this is the only place a permissions problem is visible"
}
output "xray_trace_command" {
  value       = local.outputs.xray_trace_command.value
  description = "Trace summaries for the last ten minutes, without opening the console. Empty while the pods are healthy means the pipeline is dropping them - work backwards through the two log commands above"
}
output "service_graph_command" {
  value       = local.outputs.service_graph_command.value
  description = "The same data as the console's service map. Two nodes are expected: the sample application, and the AWS service its SDK call reaches"
}
output "update_kubeconfig_command" {
  value       = local.outputs.update_kubeconfig_command.value
  description = "User data already ran this, so kubectl works out of the box. Re-run it if the kubeconfig is ever lost"
}
