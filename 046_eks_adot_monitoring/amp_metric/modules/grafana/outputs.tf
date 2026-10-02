output "namespace" {
  value       = var.namespace
  description = "Namespace Grafana and its operator run in, re-exposed so the caller's diagnostic commands read one value (rules.md B-5)"
}
output "name" {
  value       = var.name
  description = "Name of the Grafana custom resource, from which the operator derives the Deployment, Service and service account names"
}
output "service_name" {
  value       = "${var.name}-service"
  description = "Service the Ingress routes to. Derived from the custom resource's name by the operator, so it is computed here rather than restated (rules.md B-5)"
}
output "iam_role_arn" {
  value       = aws_iam_role.grafana_iam_role.arn
  description = "IRSA role Grafana assumes to query Amazon Managed Prometheus. Also attached an inline policy scoped to the single workspace, where AmazonPrometheusQueryAccess alone covers every workspace in the account"
}
output "admin_user" {
  value       = var.admin_user
  description = "Administrator login name. Not sensitive on its own; the password is not exposed here at all"
}
output "admin_secret_name" {
  value       = local.admin_secret_name
  description = "Kubernetes Secret the credential is read from. Both its name and its two key names are fixed by the operator, which injects an env pair referencing them into the Deployment it builds - a Secret of the right name holding differently named keys leaves the pod in CreateContainerConfigError"
}
output "admin_password_command" {
  value = var.secrets_manager_name == null ? (
    "kubectl -n ${var.namespace} get secret ${local.admin_secret_name} -o jsonpath='{.data.${local.admin_password_key}}' | base64 -d ; echo"
    ) : (
    "aws secretsmanager get-secret-value --secret-id ${var.secrets_manager_name} --query SecretString --output text"
  )
  description = "How to retrieve the password. A command rather than a value, because an output would write the credential into Terraform state's plaintext output section and into any CI log that prints outputs - the _monolithic template exposed it directly, alongside a default of the literal string \"grafana\" (rules.md H-2)"
}
output "datasource_name" {
  value       = var.datasource_name
  description = "Name of the data source inside Grafana, which is what a dashboard's data source picker shows"
}
output "rollout_status_command" {
  value       = "kubectl -n ${var.namespace} rollout status deployment ${var.name}-deployment --timeout=10m"
  description = "Waits for the instance the operator builds. The Helm release finishes once the operator is running, so this trails it - and the first boot is slower than later ones because Grafana installs the Amazon Prometheus plugin at startup"
}
output "datasource_status_command" {
  value       = "kubectl -n ${var.namespace} get grafanadatasource ${var.datasource_name} -o jsonpath='{.status}' ; echo"
  description = "Whether the operator applied the data source to the instance. An empty status usually means the instanceSelector matched nothing, which is accepted by the API server and reconciled into nothing"
}
output "operator_log_command" {
  value       = "kubectl -n ${var.namespace} logs deploy/grafana-operator-controller-manager --tail 100"
  description = "Where a rejected custom resource appears. The operator validates against its CRD schema and reports here; the kubectl_manifest apply succeeds regardless, because it only had to create the object"
}
output "grafana_log_command" {
  value       = "kubectl -n ${var.namespace} logs deploy/${var.name}-deployment --tail 100"
  description = "Grafana's own log. A SigV4 signature AMP rejects, or a failed plugin install, appears here and nowhere else - the data source page reports only that the query failed"
}

output "admin_env_check_command" {
  # The env the operator actually built, not the env this module asked for. Two entries per variable
  # here means something is declaring the pair the operator already injects, which is what leaves the
  # pod in CreateContainerConfigError.
  value       = "kubectl -n ${var.namespace} get deployment ${local.deployment_name} -o jsonpath='{range .spec.template.spec.containers[*].env[*]}{.name}{\" <- \"}{.valueFrom.secretKeyRef.name}{\"/\"}{.valueFrom.secretKeyRef.key}{\"\\n\"}{end}' | grep GF_SECURITY"
  description = "Lists the admin credential environment variables on the built Deployment and the Secret keys they resolve to. Exactly one entry per variable is correct; a duplicate, or a key the Secret does not hold, is what CreateContainerConfigError means here"
}

output "admin_secret_keys_command" {
  value       = "kubectl -n ${var.namespace} get secret ${local.admin_secret_name} -o jsonpath='{range $k, $v := .data}{$k}{\"\\n\"}{end}'"
  description = "The keys the Secret actually holds. They have to be exactly the two the operator's injected env reads, which is why this module does not get to name them"
}
