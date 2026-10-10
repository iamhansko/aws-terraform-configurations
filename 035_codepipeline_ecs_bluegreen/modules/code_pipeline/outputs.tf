output "pipeline_name" {
  value       = aws_codepipeline.code_pipeline.name
  description = "Name of the pipeline, which the EventBridge target names"
}
output "pipeline_arn" {
  value       = aws_codepipeline.code_pipeline.arn
  description = "ARN of the pipeline read from the resource, which is what the EventBridge rule's role is scoped to. The policy inside this module cannot use it - the role has to exist before the pipeline - so it assembles the same ARN from the name instead"
}
output "role_arn" {
  value       = aws_iam_role.code_pipeline_iam_role.arn
  description = "ARN of the pipeline service role"
}
output "role_name" {
  value       = aws_iam_role.code_pipeline_iam_role.name
  description = "Generated name of the pipeline service role"
}
output "pipeline_status_command" {
  value       = "aws codepipeline get-pipeline-state --name ${aws_codepipeline.code_pipeline.name} --query 'stageStates[].[stageName,latestExecution.status,actionStates[0].latestExecution.errorDetails.message]' --output table"
  description = "Command printing each stage with its last result and error message. A source stage that has never run means nothing triggered the pipeline; one that failed means the archive is missing or not a zip"
}
output "pipeline_execution_command" {
  value       = "aws codepipeline list-pipeline-executions --pipeline-name ${aws_codepipeline.code_pipeline.name} --max-items 5 --query 'pipelineExecutionSummaries[].[pipelineExecutionId,status,trigger.triggerType,startTime]' --output table"
  description = "Command listing recent executions with what triggered each one. A triggerType of CloudWatchEvent is the trail and rule chain working; StartPipelineExecution means somebody started it by hand"
}
output "start_pipeline_command" {
  value       = "aws codepipeline start-pipeline-execution --name ${aws_codepipeline.code_pipeline.name}"
  description = "Starts a run without uploading anything, which separates a broken trigger chain from a broken build or deployment - if this works and an upload does not, the problem is the trail or the rule"
}
