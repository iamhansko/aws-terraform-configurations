output "application_name" {
  value       = aws_codedeploy_app.code_deploy_application.name
  description = "Name of the CodeDeploy application, which the workflow passes as codedeploy-application (rules.md B-5)"
}
# The name on its own, which is what the deploy action's codedeploy-deployment-group input takes.
#
# The _monolithic template interpolated aws_codedeploy_deployment_group.code_deploy_deployment_group.id
# into the workflow instead. That attribute is "<application name>:<deployment group name>", so the
# generated workflow asked CodeDeploy for a group called "ecs-codedeploy-app:ecs-codedeploy-dg". Nothing in
# Terraform notices: the apply succeeds, the workflow file is written, and the failure arrives on the first
# push as a deploy step that cannot find the deployment group.
output "deployment_group_name" {
  value       = aws_codedeploy_deployment_group.code_deploy_deployment_group.deployment_group_name
  description = "Name of the deployment group, which the workflow passes as codedeploy-deployment-group"
}
output "deployment_group_id" {
  value       = aws_codedeploy_deployment_group.code_deploy_deployment_group.deployment_group_id
  description = "CodeDeploy's own identifier for the group, which is not the name and not what the deploy action takes"
}
output "service_role_arn" {
  value       = aws_iam_role.code_deploy_iam_role.arn
  description = "ARN of the CodeDeploy service role"
}
output "service_role_name" {
  value       = aws_iam_role.code_deploy_iam_role.name
  description = "Name of the CodeDeploy service role, for attaching extra policies from the root module"
}
output "list_deployments_command" {
  value       = "aws deploy list-deployments --application-name ${aws_codedeploy_app.code_deploy_application.name} --deployment-group-name ${aws_codedeploy_deployment_group.code_deploy_deployment_group.deployment_group_name} --query deployments --output table"
  description = "Every deployment this group has run, newest first. Empty until the first push to the branch - Terraform creates the group but never creates a deployment"
}
output "describe_latest_deployment_command" {
  value       = "aws deploy get-deployment --deployment-id $(aws deploy list-deployments --application-name ${aws_codedeploy_app.code_deploy_application.name} --deployment-group-name ${aws_codedeploy_deployment_group.code_deploy_deployment_group.deployment_group_name} --query 'deployments[0]' --output text) --query 'deploymentInfo.[status,deploymentOverview,errorInformation,rollbackInfo]' --output json"
  description = "The newest deployment in detail. errorInformation is where a replacement task set that could not be placed shows up, and rollbackInfo is where an automatic rollback says what triggered it"
}
