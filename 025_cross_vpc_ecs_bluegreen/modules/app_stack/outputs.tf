output "service_name" {
  value       = aws_ecs_service.service.name
  description = "Name of the ECS service"
}
output "task_definition_family" {
  value       = aws_ecs_task_definition.task_definition.family
  description = "Task definition family"
}
output "task_definition_template" {
  value       = local.task_definition_template
  description = "The taskdef.json every pipeline artefact for this stack carries: the task definition Terraform registers, with the application image replaced by the <IMAGE1_NAME>-style placeholder. The seed artefact is built from it here, and the artefact-building association writes the same text, so the two cannot disagree (rules.md B-5)"
}
output "app_spec_template" {
  value       = local.app_spec_template
  description = "The appspec.yaml every pipeline artefact for this stack carries, naming the same container and port as the task definition. CodeDeploy rejects a mismatch at deployment time rather than at apply"
}
output "task_definition_arn" {
  value       = aws_ecs_task_definition.task_definition.arn
  description = "ARN of the revision Terraform registered. The running service will be on a later revision after any deployment - CodeDeploy registers its own, which is why the service ignores changes to task_definition (rules.md E-8)"
}
output "container_name" {
  value       = var.container_name
  description = "Application container name, re-exposed so the appspec.yaml the association writes names the same container as the task definition. CodeDeploy rejects a mismatch at deployment time rather than at apply (rules.md B-5)"
}
output "container_port" {
  value       = var.container_port
  description = "Application container port, re-exposed for the same reason as container_name - it appears in the appspec as well"
}
output "image_uri" {
  value       = "${var.image_uri}:${var.image_tag}"
  description = "Image the task definition starts on, tag included"
}
output "repository_url" {
  value       = var.image_uri
  description = "Repository URL without a tag, re-exposed so the association writing imageDetail.json names the same repository (rules.md B-5)"
}
output "log_group_name" {
  value       = aws_cloudwatch_log_group.app_log_group.name
  description = "Application log group, which is also what the dashboard log widget queries"
}
output "target_group_blue_arn" {
  value       = aws_lb_target_group.blue.arn
  description = "The target group that is live first"
}
output "target_group_green_arn" {
  value       = aws_lb_target_group.green.arn
  description = "The replacement target group"
}
output "target_group_names" {
  value       = [aws_lb_target_group.blue.name, aws_lb_target_group.green.name]
  description = "Both target group names, which is the form CodeDeploy uses"
}
output "listener_rule_priority" {
  value       = var.listener_rule_priority
  description = "Priority of this stack's path rule, re-exposed so a collision between the two stacks and the error path rule is visible in terraform output (rules.md B-5)"
}
output "path_prefix" {
  value       = "/${var.stack_key}"
  description = "Path this stack answers on, derived from the stack key rather than passed in - the _monolithic template wrote the two patterns out per stack"
}
output "code_deploy_application_name" {
  value       = aws_codedeploy_app.code_deploy_application.name
  description = "CodeDeploy application name"
}
output "code_deploy_deployment_group_name" {
  value       = aws_codedeploy_deployment_group.code_deploy_deployment_group.deployment_group_name
  description = "CodeDeploy deployment group name"
}
output "pipeline_name" {
  value       = aws_codepipeline.code_pipeline.name
  description = "CodePipeline name"
}
output "pipeline_arn" {
  value       = aws_codepipeline.code_pipeline.arn
  description = "Pipeline ARN. The EventBridge target references this resource rather than assembling the string, which is what the _monolithic template did - and an assembled ARN carries no dependency, so the target could point at a pipeline that did not exist"
}
output "source_bucket_name" {
  value       = aws_s3_bucket.source_bucket.id
  description = "Generated source bucket name. The helper script uploads the artefact here and the EventBridge rule matches on it"
}
output "source_bucket_arn" {
  value       = aws_s3_bucket.source_bucket.arn
  description = "Source bucket ARN, which the CloudTrail data event selector names - the EventBridge rule only fires if that trail is recording writes to this object (rules.md B-6)"
}
output "source_object_key" {
  value       = var.source_object_key
  description = "Object key that starts a pipeline run, re-exposed so the helper script, the rule pattern and the trail selector read one value (rules.md B-5)"
}
output "source_object_arn" {
  value       = "${aws_s3_bucket.source_bucket.arn}/${var.source_object_key}"
  description = "Full object ARN for the CloudTrail data event selector, assembled here rather than in the trail module so the bucket and the key stay together"
}
output "artifact_store_bucket_name" {
  value       = aws_s3_bucket.artifact_store_bucket.id
  description = "Generated pipeline artifact store bucket name"
}
output "artifact_directory" {
  value       = var.stack_key
  description = "Directory name this stack's artefact is assembled in on the workbench, derived from the stack key so the association and the helper script agree"
}
output "pipeline_status_command" {
  value       = "aws codepipeline get-pipeline-state --name ${aws_codepipeline.code_pipeline.name} --query 'stageStates[].[stageName,latestExecution.status,actionStates[0].latestExecution.status]' --output table"
  description = "Command printing each stage of this pipeline and its last result"
}
output "deployment_status_command" {
  value       = "aws deploy list-deployments --application-name ${aws_codedeploy_app.code_deploy_application.name} --deployment-group-name ${aws_codedeploy_deployment_group.code_deploy_deployment_group.deployment_group_name} --query deployments --output table"
  description = "Command listing this stack's deployments, most recent first. Pair it with aws deploy get-deployment --deployment-id <id> to watch a traffic shift"
}
