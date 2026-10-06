output "virtual_cluster_id" {
  value       = aws_emrcontainers_virtual_cluster.virtual_cluster.id
  description = "ID of the EMR virtual cluster, which is what a start-job-run call names"
}

output "virtual_cluster_name" {
  value       = aws_emrcontainers_virtual_cluster.virtual_cluster.name
  description = "Name of the EMR virtual cluster"
}

output "namespace" {
  value       = var.namespace
  description = "Namespace the virtual cluster is bound to, re-exposed so a pod template does not restate it (rules.md B-5)"
}

output "job_execution_role_arn" {
  value       = aws_iam_role.job_execution.arn
  description = "ARN a start-job-run call passes as its execution role. Its trust policy matches emr-containers-sa-* in the namespace, because EMR names the service account after this role and the name is not knowable in advance"
}

output "job_execution_role_name" {
  value       = aws_iam_role.job_execution.name
  description = "Name of the job execution role, for a caller that has to attach another policy to it"
}

output "bucket_name" {
  value       = aws_s3_bucket.job.id
  description = "Job data bucket: scripts, input, output and logs"
}

output "bucket_uri" {
  value       = "s3://${aws_s3_bucket.job.id}"
  description = "The bucket as an s3:// URI, which is the form the job script uses"
}

output "log_group_name" {
  value       = aws_cloudwatch_log_group.job.name
  description = "CloudWatch log group a job's monitoringConfiguration writes to"
}

output "job_runs_command" {
  value       = "aws emr-containers list-job-runs --virtual-cluster-id ${aws_emrcontainers_virtual_cluster.virtual_cluster.id} --query 'jobRuns[].[id,name,state,stateDetails]' --output table"
  description = "Command that lists the job runs and their state. FAILED with a stateDetails line is the first place to look; the driver's own output is in the log group"
}

output "job_log_command" {
  value       = "aws logs tail ${aws_cloudwatch_log_group.job.name} --follow"
  description = "Command that follows the job's driver and executor logs. A job that reaches RUNNING and produces nothing here usually could not assume the execution role, which is a trust policy problem rather than a Spark one"
}

output "output_listing_command" {
  value       = "aws s3 ls s3://${aws_s3_bucket.job.id} --recursive --human-readable --summarize"
  description = "Command that lists everything in the job bucket. The output prefix filling with parquet files is what says the job actually did its work"
}
