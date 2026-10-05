output "repository_url" {
  value       = aws_ecr_repository.mcp_server.repository_url
  description = "Registry path of the repository, without a tag"
}

output "repository_arn" {
  value       = aws_ecr_repository.mcp_server.arn
  description = "ARN of the ECR repository"
}

output "image_uri" {
  value       = "${aws_ecr_repository.mcp_server.repository_url}:${var.image_tag}"
  description = "Full image reference the workload's Deployment uses. Derived here so the tag is written once (rules.md B-5)"
}

output "project_name" {
  value       = aws_codebuild_project.build.name
  description = "Name of the CodeBuild project, for the trigger that starts a build"
}

output "project_arn" {
  value       = aws_codebuild_project.build.arn
  description = "ARN of the project, so the trigger's codebuild:StartBuild can be scoped to this one rather than to every project in the account (rules.md A-5)"
}

output "log_group_name" {
  value       = aws_cloudwatch_log_group.build.name
  description = "Build log group, which is where a docker build failure is explained"
}

output "build_status_command" {
  value       = "aws codebuild batch-get-builds --ids $(aws codebuild list-builds-for-project --project-name ${aws_codebuild_project.build.name} --max-items 1 --query 'ids[0]' --output text) --query 'builds[].[buildStatus,currentPhase,phases[?phaseStatus==`FAILED`].[phaseType,contexts[0].message]]' --output json"
  description = "Command that shows the most recent build's status and, if it failed, which phase and why"
}

output "images_check_command" {
  value       = "aws ecr list-images --repository-name ${aws_ecr_repository.mcp_server.name} --query 'imageIds' --output table"
  description = "Command that lists the images in the repository. An empty list while pods sit in ImagePullBackOff means the build never pushed, which the build status command above explains"
}

output "start_build_command" {
  value       = "aws codebuild start-build --project-name ${aws_codebuild_project.build.name} --query 'build.id' --output text"
  description = "Command that rebuilds and repushes the image by hand, for when the Dockerfile changed but the apply did not"
}
output "build_revision" {
  value       = sha256(local.buildspec)
  description = <<-DESC
    Hash of the buildspec, which is also a hash of the Dockerfile because the Dockerfile travels inside
    it. Exists so that a caller starting builds can start a new one when the definition changes.

    Why it is needed: the thing that starts a build is a one-shot Lambda invocation, and an invocation
    re-runs only when its own arguments change. Its argument is the project name, which does not change
    when the Dockerfile does - so editing the Dockerfile produced a plan that updated the CodeBuild
    project, applied cleanly, and built nothing. The image in ECR stayed whatever the last successful
    build had pushed, or stayed absent. Passing this value into the trigger's triggers map is what makes
    "the build definition changed" and "a build runs" the same event.

    A plan-time value, taken from the local rather than read back off the resource, so the trigger's
    decision is visible in the plan instead of being deferred to apply.
  DESC
}
