# Every value here is a projection of local.outputs in main.tf, which the README written onto the workbench
# renders from the same map - so no value expression exists twice, and an output cannot be added without
# also appearing in that README (rules.md B-5/H-2).
#
# description is the one thing that cannot be projected: Terraform rejects an expression in an output's
# description ("Variables not allowed"), so the wording is a literal on both sides.
#
# Nothing here is sensitive, and that is deliberate rather than lucky. The GitHub token and the generated
# SSH private key are both exposed as retrieval commands, because this same map is written to a file served
# by a code-server running with auth: none - a value marked sensitive would still be in that file in plain
# text (rules.md H-2).
output "vscode_url" {
  value       = local.outputs.vscode_url.value
  description = "The workbench. Every command below is meant to be run from its terminal, and the repository the pipeline deploys is checked out in the directory it opens"
}
output "connection_authorization_step" {
  value       = local.outputs.connection_authorization_step.value
  description = "A CodeStar connection is created in PENDING and only becomes AVAILABLE when a person completes the GitHub handshake in the console. Nothing fails until then - the apply succeeds and the connection simply is not usable. Open this page, select the connection below, and choose Update pending connection"
}
output "connection_status_command" {
  value       = local.outputs.connection_status_command.value
  description = "AVAILABLE once the handshake above is done. PENDING is the state every new connection is created in"
}
output "connection_name" {
  value       = local.outputs.connection_name.value
  description = "Name of the connection to select on that page. Note that nothing in this project consumes it: CodeBuild authenticates to GitHub with the personal access token credential instead, which is the resource the AWS provider documents for that job. The connection is reproduced because the _monolithic template created it"
}
output "application_url" {
  value       = local.outputs.application_url.value
  description = "Served by whichever target group the listener currently forwards to. / returns the greeting and /tag returns the TAG constant from cicd-app.py, which is how a deployment is observed from outside"
}
output "application_tag_command" {
  value       = local.outputs.application_tag_command.value
  description = "Poll the tag route while a deployment runs. With CodeDeployDefault.ECSAllAtOnce the value changes in one step, which is the moment the listener was rewritten"
}
output "trigger_deployment_step" {
  value       = local.outputs.trigger_deployment_step.value
  description = "Edit the TAG constant in cicd-app.py, commit and push. The workflow builds a new image, renders a task definition from taskdef.json and hands it to CodeDeploy. Setting TAG to exactly \"fargate\" makes the workflow's Fargate branch deploy the replacement task set onto Fargate instead of the container instances"
}
output "live_target_group_command" {
  value       = local.outputs.live_target_group_command.value
  description = "The field CodeDeploy rewrites on every deployment, and the one this configuration deliberately stops tracking - so the listener itself is the only honest answer"
}
output "target_health_command" {
  value       = local.outputs.target_health_command.value
  description = "Exactly one group holds healthy targets between deployments, and both do briefly during a cutover. Targets stuck unhealthy with Target.Timeout is a security group path problem rather than an application one"
}
output "service_status_command" {
  value       = local.outputs.service_status_command.value
  description = "Two task sets with one PRIMARY and one ACTIVE is a cutover in progress. One left behind afterwards is a deployment that was stopped rather than completed"
}
output "service_events_command" {
  value       = local.outputs.service_events_command.value
  description = "Where a pull failure or a task that could not be placed is reported first. \"unable to place a task because no container instance met all of its requirements\" during a cutover is the capacity provider's instance ceiling rather than a placement constraint"
}
output "latest_deployment_command" {
  value       = local.outputs.latest_deployment_command.value
  description = "errorInformation is where a replacement task set that could not be placed shows up, and rollbackInfo is where an automatic rollback says what triggered it"
}
output "build_log_command" {
  value       = local.outputs.build_log_command.value
  description = "Live output from the CodeBuild project acting as the self-hosted runner. This is where the workflow's docker build, render and deploy steps report, and where a permission the scoped build role is missing names the call it needed"
}
output "list_builds_command" {
  value       = local.outputs.list_builds_command.value
  description = "Empty while a GitHub job sits queued means the webhook never fired or its label does not match the project name. The _monolithic template lost the webhook entirely in conversion, and a project without one never starts a build"
}
output "list_images_command" {
  value       = local.outputs.list_images_command.value
  description = "One image from the workbench's seed push, and one per workflow run after that"
}
output "list_task_definitions_command" {
  value       = local.outputs.list_task_definitions_command.value
  description = "Revision 1 is Terraform's. Every later one was registered by a workflow run, which is why the service's task_definition field is not tracked"
}
output "container_instances_command" {
  value       = local.outputs.container_instances_command.value
  description = "An empty list while the Auto Scaling group reports healthy instances means an instance that cannot reach the ECS endpoint - it never becomes an ECS object that could report a problem, and the service blames placement instead"
}
output "capacity_command" {
  value       = local.outputs.capacity_command.value
  description = "DesiredCapacity differing from what the configuration declares is expected rather than drift: ECS managed scaling owns that field. MaxSize is 2 rather than the original's 1, so a blue/green cutover has somewhere to put the replacement task set"
}
output "cluster_name" {
  value       = local.outputs.cluster_name.value
  description = "Name of the ECS cluster"
}
output "service_name" {
  value       = local.outputs.service_name.value
  description = "Name of the ECS service, which the workflow and the CodeDeploy deployment group both name"
}
output "task_family" {
  value       = local.outputs.task_family.value
  description = "The family exported to taskdef.json in the repository, and the family every revision the workflow registers belongs to"
}
output "capacity_provider_name" {
  value       = local.outputs.capacity_provider_name.value
  description = "Named in the appspec for the replacement task set. The workflow's Fargate branch swaps this value for FARGATE"
}
output "blue_target_group_name" {
  value       = local.outputs.blue_target_group_name.value
  description = "The half of the pair the listener forwards to at creation - unless initial_target_group_key was changed, in which case the live group output says otherwise"
}
output "green_target_group_name" {
  value       = local.outputs.green_target_group_name.value
  description = "The other half. CodeDeploy works out which is which by reading the listener"
}
output "initial_target_group_key" {
  value       = local.outputs.initial_target_group_key.value
  description = "Which half of the pair the listener, the service and CodeDeploy all started out agreeing on"
}
output "code_deploy_application_name" {
  value       = local.outputs.code_deploy_application_name.value
  description = "Name the workflow passes as codedeploy-application"
}
output "code_deploy_deployment_group_name" {
  value       = local.outputs.code_deploy_deployment_group_name.value
  description = "Name the workflow passes as codedeploy-deployment-group. The _monolithic template interpolated the resource's id here, which is \"<application>:<group>\" - a value CodeDeploy has no group under, and a failure that only arrives on the first push"
}
output "code_build_project_name" {
  value       = local.outputs.code_build_project_name.value
  description = "The self-hosted runner. The workflow's runs-on label is codebuild-<this>-<run id>-<run attempt>, built from this name so the two cannot disagree"
}
output "runner_label_prefix" {
  value       = local.outputs.runner_label_prefix.value
  description = "What GitHub matches a queued job against, before the run id and run attempt are appended"
}
output "repository_clone_url" {
  value       = local.outputs.repository_clone_url.value
  description = "Where the seed commit was pushed. It has to exist before the apply: the CloudFormation resource that used to create it (AWS::CodeStar::GitHubRepository) is a legacy type with no provider equivalent, so this project only pushes to it"
}
output "source_bucket_name" {
  value       = local.outputs.source_bucket_name.value
  description = "Holds src.zip, a copy of the seeded repository. Nothing reads it - it is where the CloudFormation GitHub repository resource used to take its initial code from. terraform destroy empties it"
}
output "github_token_command" {
  value       = local.outputs.github_token_command.value
  description = "Retrieves the token from Parameter Store. A command rather than the value: the README this map is also written to is served by a code-server with no authentication, so no secret is written into it (rules.md H-2)"
}
output "private_key_command" {
  value       = local.outputs.private_key_command.value
  description = "Retrieves the generated private key from Parameter Store, for the case where the SSM agent is what is broken"
}
output "ssh_command" {
  value       = local.outputs.ssh_command.value
  description = "sshd was moved off port 22 by the bootstrap, and this command carries the port it was actually moved to - the _monolithic template's comment said one port while its security group opened another"
}
