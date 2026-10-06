# Every value here is a projection of local.outputs in main.tf. No output in this file builds its
# own expression: the same map feeds the README written onto the bastion, and an output declared
# outside it would be missing from that README with nothing to signal the gap (rules.md H-2).
#
# description is the one thing that cannot come from the map. Terraform rejects an expression in an
# output's description ("Variables not allowed"), so the wording is literal in both places while the
# value stays in one.

output "vscode_url" {
  value       = local.outputs.vscode_url.value
  description = "Open the IDE here and run the job from its terminal"
}

output "cluster_name" {
  value       = local.outputs.cluster_name.value
  description = "Name of the EKS cluster the virtual cluster is backed by"
}

output "emr_virtual_cluster_id" {
  value       = local.outputs.emr_virtual_cluster_id.value
  description = "The ID a start-job-run call names"
}

output "emr_job_execution_role_arn" {
  value       = local.outputs.emr_job_execution_role_arn.value
  description = "The role a Spark job assumes"
}

output "emr_bucket" {
  value       = local.outputs.emr_bucket.value
  description = "Scripts, input, output and logs"
}

output "aws_auth_check_command" {
  value       = local.outputs.aws_auth_check_command.value
  description = "Two entries: the EMR service-linked role and the node instance role"
}

output "emr_access_check_command" {
  value       = local.outputs.emr_access_check_command.value
  description = "Asks the API server the exact question CreateVirtualCluster asks"
}

output "upload_job_command" {
  value       = local.outputs.upload_job_command.value
  description = "Downloads one month of NYC taxi trip data, copies it enough times to give the executors something to do, and syncs both it and the scripts into the bucket"
}

output "start_job_command" {
  value       = local.outputs.start_job_command.value
  description = "Every path and ID in it was substituted by Terraform"
}

output "job_runs_command" {
  value       = local.outputs.job_runs_command.value
  description = "PENDING while Karpenter provisions an m5 node for the driver, then RUNNING, then COMPLETED"
}

output "spark_pods_command" {
  value       = local.outputs.spark_pods_command.value
  description = "EMR creates them in the namespace with the pod templates Terraform rendered"
}

output "job_log_command" {
  value       = local.outputs.job_log_command.value
  description = "The driver's own output"
}

output "output_listing_command" {
  value       = local.outputs.output_listing_command.value
  description = "Parquet files under the output prefix are what say the job did its work rather than just finishing"
}

output "update_kubeconfig_command" {
  value       = local.outputs.update_kubeconfig_command.value
  description = "User data already ran this, so kubectl works out of the box"
}
