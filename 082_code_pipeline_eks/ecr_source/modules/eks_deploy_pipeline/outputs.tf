output "pipeline_name" {
  value       = aws_codepipeline.pipeline.name
  description = "Name of the pipeline"
}
output "pipeline_arn" {
  value       = aws_codepipeline.pipeline.arn
  description = "ARN of the pipeline, for an EventBridge rule that has to target it"
}
output "pipeline_role_arn" {
  value       = aws_iam_role.pipeline.arn
  description = "ARN of the pipeline's role. The deploy stage talks to the cluster's API server as this principal, so the caller has to give it an EKS access entry - without one the stage fails with an authentication error rather than a permissions one (rules.md C-1)"
}
output "pipeline_role_name" {
  value       = aws_iam_role.pipeline.name
  description = "Name of that role, for attaching anything further from the caller"
}
output "build_project_name" {
  value       = aws_codebuild_project.build.name
  description = "Name of the CodeBuild project that renders the manifest"
}
output "artifact_bucket_name" {
  value       = aws_s3_bucket.artifacts.id
  description = "Name of the artifact bucket, generated unless one was given so that two deployments in one account do not collide"
}
output "workload_name" {
  value       = var.workload_name
  description = "Name of the Deployment and Service the pipeline renders, re-exposed so the caller's pre-created load balancer carries the matching stack tag (rules.md B-5/G-3)"
}
output "workload_namespace" {
  value       = var.workload_namespace
  description = "Namespace it is applied into, re-exposed for the same reason"
}
output "rendered_manifest" {
  value       = local.rendered_manifest
  description = "The manifest the build stage writes out, with the image URI and the two identifiers still as shell variables. Re-exposed because it is otherwise invisible until a build has run - and it is the thing most likely to be wrong"
}
output "stage_names" {
  value       = [for stage in aws_codepipeline.pipeline.stage : stage.name]
  description = "The stages this pipeline has, in order. Three for a source that already holds an image, four for one that holds a source tree - which is the difference between this project's variants"
}
output "execution_command" {
  value       = "aws codepipeline start-pipeline-execution --name ${aws_codepipeline.pipeline.name}"
  description = "Starts the pipeline by hand, for when you want a run without producing the source event that normally triggers it"
}
output "state_command" {
  value       = "aws codepipeline get-pipeline-state --name ${aws_codepipeline.pipeline.name} --query 'stageStates[].[stageName,latestExecution.status,actionStates[0].latestExecution.status]' --output table"
  description = "Every stage and how its last run ended. This is where a deploy stage that could not authenticate to the cluster shows up, and the error message names the access entry rather than the permissions"
}
output "build_log_command" {
  value       = "aws logs tail ${aws_cloudwatch_log_group.build.name} --since 30m"
  description = "The build stage's log, which now has a retention period rather than being kept forever. The rendered manifest is printed there, so a deploy stage that failed on a malformed manifest can be diagnosed from it"
}
