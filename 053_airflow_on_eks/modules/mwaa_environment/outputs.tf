output "environment_name" {
  value       = aws_mwaa_environment.mwaa.name
  description = "Name of the MWAA environment"
}
output "environment_arn" {
  value       = aws_mwaa_environment.mwaa.arn
  description = "ARN of the MWAA environment"
}
output "webserver_url" {
  value       = "https://${aws_mwaa_environment.mwaa.webserver_url}"
  description = "Airflow web server address. Opening it directly shows MWAA's sign-in redirect; login_url_command produces a link that signs in through IAM"
}
output "execution_role_arn" {
  value       = aws_iam_role.execution.arn
  description = "ARN of the environment's execution role - the identity every DAG task runs as, and so the principal the root grants EKS access and EMR job submission to"
}
output "execution_role_name" {
  value       = aws_iam_role.execution.name
  description = "Name of the execution role, for attaching a policy from the root"
}
output "security_group_id" {
  value       = aws_security_group.mwaa.id
  description = "ID of the environment's security group, which the EKS cluster security group admits on 443 so the workers can reach the API server's private endpoint"
}
output "source_bucket_name" {
  value       = aws_s3_bucket.source.id
  description = "Name of the source bucket holding the DAGs, requirements.txt and the kubeconfig"
}
output "dag_s3_uri" {
  value       = "s3://${aws_s3_bucket.source.id}/${var.dag_s3_path}/"
  description = "Where the DAG files are. MWAA syncs this prefix to /usr/local/airflow/dags on every component, so a file that is here but missing from the UI is a parse error rather than a sync problem"
}
output "status_command" {
  value       = "aws mwaa get-environment --name ${aws_mwaa_environment.mwaa.name} --query 'Environment.{Status:Status,Airflow:AirflowVersion,Requirements:RequirementsS3ObjectVersion,LastUpdate:LastUpdate.Status}' --output table"
  description = "Environment status. CREATING and UPDATING each take 20-30 minutes; a login page that will not load usually means one of those rather than anything being wrong"
}
output "login_url_command" {
  value       = "aws mwaa create-web-login-token --name ${aws_mwaa_environment.mwaa.name} --query '[WebServerHostname,WebToken]' --output text | awk '{printf \"https://%s/aws_mwaa/aws-console-sso?login=true#%s\\n\", $1, $2}'"
  description = "Prints a one-time sign-in link for the Airflow UI. The caller needs airflow:CreateWebLoginToken on this environment; the link expires after 60 seconds, so open it right away"
}
output "task_logs_command" {
  value       = "aws logs tail airflow-${aws_mwaa_environment.mwaa.name}-Task --follow"
  description = "Follows the task logs, which is where a failed operator's traceback lands"
}
output "dag_processing_logs_command" {
  value       = "aws logs tail airflow-${aws_mwaa_environment.mwaa.name}-DAGProcessing --since 30m"
  description = "The DAG processor's logs. A DAG that is in the bucket but not in the UI failed to import, and the reason is here"
}
output "connections_prefix" {
  value       = local.connections_prefix
  description = "Secrets Manager prefix the environment's secrets backend looks connections up under - a connection with ID <id> is the secret <prefix>/<id>"
}
output "connection_secret_names" {
  value       = { for id, secret in aws_secretsmanager_secret.connection : id => secret.name }
  description = "Secret name of each connection this module stored, keyed by connection ID. Names only - the connection values stay in the secret versions, which the provider marks sensitive"
}
