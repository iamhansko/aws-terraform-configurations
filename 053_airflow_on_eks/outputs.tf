# Values are all projections of local.outputs in main.tf, so no expression is written twice and the
# README the SSM association writes cannot fall behind this file (rules.md B-5/H-2).
#
# description is the one thing that cannot come from the map: Terraform rejects an expression in an
# output's description with "Variables not allowed", so the wording exists literally in both places.
# The values do not.
output "vscode_url" {
  value       = local.outputs.vscode_url.value
  description = "Open the IDE here. The kubectl and aws commands below are meant to be run from its terminal. This editor has no authentication and the instance role behind it is AdministratorAccess with cluster-admin on the cluster, so do not leave it reachable from the internet longer than the demo needs"
}
output "mwaa_status_command" {
  value       = local.outputs.mwaa_status_command.value
  description = "MWAA takes 20-30 minutes to create and as long again for every update. A login page that will not load usually means this still says CREATING or UPDATING rather than anything being wrong"
}
output "airflow_login_command" {
  value       = local.outputs.airflow_login_command.value
  description = "Prints a one-time sign-in link. MWAA signs you in through IAM, so whoever runs this needs airflow:CreateWebLoginToken - the workbench's role has it. The link is valid for 60 seconds, so open it right away"
}
output "emr_connection_command" {
  value       = local.outputs.emr_connection_command.value
  description = "Nothing to add by hand: Terraform stores the connection the EMR DAG reads in Secrets Manager, and the environment's secrets backend finds it there. It does not appear under Admin > Connections, which lists only the metadata database. This prints exactly what the DAG gets - the virtual cluster ID and the job role ARN in extra"
}
output "emr_pods_command" {
  value       = local.outputs.emr_pods_command.value
  description = "MWAA creates DAGs paused, so unpause emr_eks_pi_job in the UI; it runs once. The job it submits appears here as a job submitter pod, then a Spark driver and its executors - in the EMR namespace, not in MWAA's"
}
output "emr_job_runs_command" {
  value       = local.outputs.emr_job_runs_command.value
  description = "The job's state from EMR's side. FAILED comes with a stateDetails line, which is the first place to look; a run that never appears means the task could not call StartJobRun, which the task log shows"
}
output "emr_job_log_command" {
  value       = local.outputs.emr_job_log_command.value
  description = "The job's monitoringConfiguration writes here, which is the group the job execution role may write to. pi.py prints its estimate of pi near the end"
}
output "pod_example_command" {
  value       = local.outputs.pod_example_command.value
  description = "The second DAG runs one ubuntu pod through the KubernetesPodOperator, using the kubeconfig in its DAG folder and the namespace-scoped Role it is granted. It has no schedule, so trigger it from the UI. The pod is kept after it finishes, so this shows its output"
}
output "mwaa_rbac_check_command" {
  value       = local.outputs.mwaa_rbac_check_command.value
  description = "The execution role is authenticated as this user and granted only a Role in the namespace. A \"no\" on any line is the pod task failing with 403 Forbidden"
}
output "task_logs_command" {
  value       = local.outputs.task_logs_command.value
  description = "Where a failed operator's traceback lands - a missing connection, a 403 from the API server or an AccessDenied from EMR"
}
output "dag_import_errors_command" {
  value       = local.outputs.dag_import_errors_command.value
  description = "A DAG file that is in the bucket but not in the UI failed to import, and the DAG processor says why"
}
output "dag_files_command" {
  value       = local.outputs.dag_files_command.value
  description = "Both DAGs, requirements.txt and the kubeconfig the pod DAG uses, all written by Terraform. Edit them through main.tf and dags/ rather than here: the next apply puts Terraform's version back"
}
output "mwaa_webserver_url" {
  value       = local.outputs.mwaa_webserver_url.value
  description = "The web server's address. Opening it directly lands on MWAA's sign-in redirect rather than the UI - use the sign-in link"
}
output "cluster_name" {
  value       = local.outputs.cluster_name.value
  description = "Name of the EKS cluster, which the blueprint named after its name variable like everything else"
}
output "cluster_endpoint" {
  value       = local.outputs.cluster_endpoint.value
  description = "API server endpoint. Public so the helm and kubectl providers can reach it during apply - narrow public_access_cidrs to your own address"
}
output "cluster_nodes_command" {
  value       = local.outputs.cluster_nodes_command.value
  description = "The core node group, three m5.xlarge across three zones to start. The cluster autoscaler adds nodes when a Spark job's executors do not fit"
}
output "autoscaler_status_command" {
  value       = local.outputs.autoscaler_status_command.value
  description = "The status the autoscaler keeps for every node group it manages. An empty list means auto-discovery matched nothing, which looks the same as a cluster that simply needs no more nodes"
}
output "emr_virtual_cluster_id" {
  value       = local.outputs.emr_virtual_cluster_id.value
  description = "The connection's virtual_cluster_id, on its own"
}
output "emr_job_role_arn" {
  value       = local.outputs.emr_job_role_arn.value
  description = "The connection's job_role_arn, on its own"
}
output "update_kubeconfig_command" {
  value       = local.outputs.update_kubeconfig_command.value
  description = "User data already ran this, so kubectl works out of the box. Re-run it if the kubeconfig is ever lost"
}
output "teardown_command" {
  value       = local.outputs.teardown_command.value
  description = "One destroy removes everything, because everything is in this state now - the _monolithic template needed the blueprint's cleanup.sh run from inside the instance first. MWAA's deletion alone takes 20-30 minutes. The connection secret goes at once rather than after Secrets Manager's 30-day recovery window, so applying again straight after does not collide with its name. Left behind: the airflow-<name>-* log groups MWAA creates for itself, which no Terraform resource owns"
}
