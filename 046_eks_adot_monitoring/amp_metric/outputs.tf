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
  description = "Name of the EKS cluster, which the AWS Load Balancer Controller also writes into the elbv2.k8s.aws/cluster tag on load balancers it owns"
}
output "cluster_endpoint" {
  value       = local.outputs.cluster_endpoint.value
  description = "API server endpoint. Public so the helm and kubectl providers could reach it during apply - narrow public_access_cidrs to your own address"
}
output "grafana_url" {
  value       = local.outputs.grafana_url.value
  description = "The console, served by the ingress controller behind the pre-created NLB. The address is known from state because Terraform created that load balancer and the AWS controller adopted it (rules.md G-3). The first request can be a minute or two early: Grafana installs the Amazon Prometheus plugin at startup"
}
output "grafana_admin_user" {
  value       = local.outputs.grafana_admin_user.value
  description = "The administrator user name. The password is deliberately not an output - the _monolithic template printed it and defaulted it to the literal string \"grafana\"; use the command below instead (rules.md H-2)"
}
output "grafana_admin_password_command" {
  value       = local.outputs.grafana_admin_password_command.value
  description = "A command rather than a value, because an output would write the credential into state's plaintext output section and into any log that prints outputs. It is generated unless grafana_admin_password was set"
}
output "amp_workspace" {
  value       = local.outputs.amp_workspace.value
  description = "The ws-<uuid> everything actually references, and the alias the console lists. Metrics arrive here by remote write from the collector and leave by SigV4-signed query from Grafana"
}
output "amp_endpoints" {
  value       = local.outputs.amp_endpoints.value
  description = "Two different URLs from one base, which is worth keeping straight: the collector needs the remote write path appended, and Grafana's data source takes the base as-is. Swapping them produces 404s in the collector log or 405s in Grafana, and nothing else reports either"
}
output "amp_log_groups" {
  value       = local.outputs.amp_log_groups.value
  description = "Rule evaluation errors and served queries. Both are under /aws/vendedlogs, which is what lets AMP write to them without a log group resource policy - and the query one is connected, which the _monolithic template's was not: its CloudFormation source configured query logging and cfn2tf could not map the property"
}
output "addon_configuration" {
  value       = local.outputs.addon_configuration.value
  description = "The JSON the adot add-on received. Read it first when no metrics arrive: a key in the wrong place is valid JSON the add-on ignores, and nothing anywhere reports that (rules.md E-5)"
}
output "collector_role" {
  value       = local.outputs.collector_role.value
  description = "The IRSA role the Prometheus collector assumes. It carries both a Prometheus and a CloudWatch policy because two pipelines read the same scrape - remote write to the workspace, and embedded metric format to CloudWatch"
}
output "grafana_role" {
  value       = local.outputs.grafana_role.value
  description = "The role Grafana assumes to query the workspace. Also carries an inline policy scoped to this one workspace, where AmazonPrometheusQueryAccess alone covers every workspace in the account"
}
output "permission_check_command" {
  value       = local.outputs.permission_check_command.value
  description = "The RBAC that lets the eks:addon-manager user create the operator. If the add-on reports a create failure, the message names the object it could not create and every one of them is covered here"
}
output "collector_status_command" {
  value       = local.outputs.collector_status_command.value
  description = "An OpenTelemetryCollector with no matching workload means the operator has not reconciled it, which is almost always its webhook failing to serve - check cert-manager before anything else"
}
output "series_count_command" {
  value       = local.outputs.series_count_command.value
  description = "Counts every series in the workspace, which is the shortest answer to whether remote write is working. Needs awscurl because the endpoint requires SigV4 - a plain curl gets a 403 that reads as a permissions problem rather than an unsigned request"
}
output "adopted_load_balancer_check_command" {
  value       = local.outputs.adopted_load_balancer_check_command.value
  description = "Lists every load balancer tagged for this cluster. One is correct. Two means the AWS controller did not adopt the pre-created one and built its own, which is a tag mismatch rather than an error (rules.md G-3)"
}
output "ingress_hostname_command" {
  value       = local.outputs.ingress_hostname_command.value
  description = "Compare this against the Grafana URL above. They should be the same load balancer"
}
output "grafana_rollout_command" {
  value       = local.outputs.grafana_rollout_command.value
  description = "The Helm release finishes once the operator is running, so the instance it builds trails it. The first boot is the slow one, because the Amazon Prometheus plugin is installed at startup"
}
output "datasource_status_command" {
  value       = local.outputs.datasource_status_command.value
  description = "An empty status usually means the instanceSelector matched nothing, which is accepted by the API server and reconciled into nothing - so the data source never appears in the UI"
}
output "grafana_log_command" {
  value       = local.outputs.grafana_log_command.value
  description = "Where a SigV4 signature AMP rejected, or a failed plugin install, appears. The data source page reports only that the query failed"
}
output "collector_log_command" {
  value       = local.outputs.collector_log_command.value
  description = "The other end of the same question. An AccessDenied from AMP or CloudWatch appears here and nowhere else - the collector stays Running either way"
}
output "update_kubeconfig_command" {
  value       = local.outputs.update_kubeconfig_command.value
  description = "User data already ran this, so kubectl works out of the box. Re-run it if the kubeconfig is ever lost"
}
