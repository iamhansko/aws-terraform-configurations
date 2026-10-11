output "repository_name" {
  value       = aws_ecr_repository.comfyui.name
  description = "Name of the repository the image is pushed to"
}
output "repository_url" {
  value       = aws_ecr_repository.comfyui.repository_url
  description = "URL of the repository, without a tag"
}
output "image_uri" {
  value       = "${aws_ecr_repository.comfyui.repository_url}:${var.image_tag}"
  description = "Full image reference the build pushes and the Deployment pulls, built from the same repository and tag the build is configured with (rules.md B-5)"
}
output "project_name" {
  value       = aws_codebuild_project.build.name
  description = "Name of the CodeBuild project, for the root's build action"
}
output "project_arn" {
  value       = aws_codebuild_project.build.arn
  description = "ARN of the CodeBuild project"
}
output "build_timeout_minutes" {
  value       = var.build_timeout_minutes
  description = "The project's build timeout, re-exposed so the root's action waits on the same number rather than restating it (rules.md B-5)"
}
output "log_group_name" {
  value       = aws_cloudwatch_log_group.build.name
  description = "Log group the build writes to"
}
output "build_status_command" {
  value       = "aws codebuild batch-get-builds --ids $(aws codebuild list-builds-for-project --project-name ${aws_codebuild_project.build.name} --max-items 1 --query 'ids[0]' --output text) --query 'builds[0].{Status:buildStatus,Phase:currentPhase,Started:startTime}' --output table"
  description = "Status of the most recent image build"
}
output "start_build_command" {
  value       = "aws codebuild start-build --project-name ${aws_codebuild_project.build.name} --query 'build.id' --output text"
  description = "Starts a rebuild by hand. Running pods keep the image they started with; restart the Deployment to pull the new one"
}
output "images_command" {
  value       = "aws ecr describe-images --repository-name ${aws_ecr_repository.comfyui.name} --query 'sort_by(imageDetails,&imagePushedAt)[-3:].{Tags:join(`,`,imageTags||`[]`),Pushed:imagePushedAt,Bytes:imageSizeInBytes}' --output table"
  description = "The three most recent images in the repository and when they were pushed"
}
