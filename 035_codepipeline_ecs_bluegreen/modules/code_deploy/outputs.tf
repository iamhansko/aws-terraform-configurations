output "application_name" {
  value       = aws_codedeploy_app.code_deploy_application.name
  description = "Name of the CodeDeploy application, which the pipeline's deploy action names"
}
output "application_arn" {
  value       = aws_codedeploy_app.code_deploy_application.arn
  description = "ARN of the application. The pipeline role's RegisterApplicationRevision statement is scoped to this"
}
output "deployment_group_name" {
  value       = aws_codedeploy_deployment_group.code_deploy_deployment_group.deployment_group_name
  description = "Name of the deployment group. The declared name rather than the resource's id, which for this resource is the generated deployment group id - the pipeline's deploy action needs the name, and an id there is accepted by every Terraform check and then fails when the stage runs"
}
output "deployment_group_id" {
  value       = aws_codedeploy_deployment_group.code_deploy_deployment_group.deployment_group_id
  description = "CodeDeploy's own generated id for the group, exposed because it is what appears in the console URL"
}
output "role_arn" {
  value       = aws_iam_role.code_deploy_iam_role.arn
  description = "ARN of the CodeDeploy service role"
}
output "role_name" {
  value       = aws_iam_role.code_deploy_iam_role.name
  description = "Generated name of the CodeDeploy service role"
}
output "deployment_status_command" {
  value       = "aws deploy list-deployments --application-name ${aws_codedeploy_app.code_deploy_application.name} --deployment-group-name ${aws_codedeploy_deployment_group.code_deploy_deployment_group.deployment_group_name} --query deployments --output text | tr '\\t' '\\n' | head -5 | xargs -r -n1 -I{} aws deploy get-deployment --deployment-id {} --query 'deploymentInfo.[deploymentId,status,errorInformation.message]' --output text"
  description = "Command listing recent deployments with their status and error message. This is where a wrong capacity provider or a string ContainerPort in the appspec surfaces - the build goes green and the deployment fails"
}
output "target_set_command" {
  value       = "aws deploy list-deployments --application-name ${aws_codedeploy_app.code_deploy_application.name} --deployment-group-name ${aws_codedeploy_deployment_group.code_deploy_deployment_group.deployment_group_name} --query 'deployments[0]' --output text | xargs -r -I{} aws deploy get-deployment-target --deployment-id {} --target-id ${var.cluster_name}:${var.service_name} --query 'deploymentTarget.ecsTarget.taskSetsInfo' --output json"
  description = "Command showing the two task sets of the latest deployment with their traffic weights and target groups. This is the blue/green switch itself: weight moves from one target group to the other, and the old task set then goes away"
}
