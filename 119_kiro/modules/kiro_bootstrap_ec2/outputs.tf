output "instance_id" {
  value       = aws_instance.bootstrap.id
  description = "ID of the one-shot bootstrap instance"
}

output "completion_association_id" {
  value       = aws_ssm_association.bootstrap_complete.id
  description = "ID of the SSM Association that invokes the custom bootstrap Command document operation"
}

output "bootstrap_completion_wait_id" {
  value       = terraform_data.bootstrap_completion_wait.id
  description = "Terraform waiter ID that verifies the password and blocks stop and outputs until this EC2 instance has verified status"
}

output "cleanup_association_id" {
  value       = var.subscription_cleanup_generation == null ? null : aws_ssm_association.subscription_cleanup[0].id
  description = "ID of the cleanup operation Association, or null while teardown cleanup is disabled"
}

output "cleanup_wait_id" {
  value       = var.subscription_cleanup_generation == null ? null : terraform_data.subscription_cleanup_wait[0].id
  description = "Terraform waiter ID proving the exact cleanup request succeeded, or null while cleanup is disabled"
}

output "cleanup_request_id" {
  value       = var.subscription_cleanup_generation == null ? null : terraform_data.subscription_cleanup_request[0].id
  description = "Unique cleanup request ID generated for the current teardown generation"
}

output "subscription_cleanup_generation" {
  value       = var.subscription_cleanup_generation
  description = "Current teardown cleanup generation, or null during normal operation"
}

output "marker_file_path" {
  value       = local.marker_file_path
  description = "Ephemeral directory used only by the SSM bootstrap script for same-boot diagnostics; durable status remains in SSM Parameter Store"
}

output "password_parameter_name" {
  value       = aws_ssm_parameter.password.name
  description = "SecureString parameter containing the one-time password"
}

output "bootstrap_status_parameter_name" {
  value       = aws_ssm_parameter.bootstrap_status.name
  description = "SSM parameter carrying instance-specific bootstrap completion status"
}

output "cleanup_status_parameter_name" {
  value       = aws_ssm_parameter.cleanup_status.name
  description = "SSM parameter carrying request-specific subscription cleanup status"
}

output "profile_ownership_parameter_name" {
  value       = aws_ssm_parameter.profile_ownership.name
  description = "SSM parameter recording whether this root owns the state-external Kiro profile"
}

output "subscription_ownership_parameter_name" {
  value       = aws_ssm_parameter.subscription_ownership.name
  description = "SSM parameter recording whether this root owns the state-external Kiro subscription"
}

output "password_placeholder" {
  value       = local.password_placeholder
  description = "Non-secret initial sentinel used by the completion check"
}

output "aws_region" {
  value       = var.aws_region
  description = "AWS region containing the bootstrap instance and password parameter"
}

output "kiro_region" {
  value       = var.kiro_region
  description = "Kiro profile/assignment region and ListUserSubscriptions subscriptionRegion selector (rules.md B-5)"
}

output "kiro_subscription_plan" {
  value       = var.create_kiro_subscription ? var.kiro_subscription_plan : null
  description = "Requested Kiro plan, or null when subscription creation is disabled"
}

output "subscription_requested" {
  value       = var.create_kiro_subscription
  description = "Whether the custom bootstrap Command document creates and observes a billed Kiro subscription"
}

output "role_arn" {
  value       = aws_iam_role.bootstrap.arn
  description = "ARN of the bootstrap role, which remains attached until terraform destroy even after the instance is stopped"
}

output "bootstrap_association_executions_command" {
  value       = "aws ssm describe-association-executions --region ${var.aws_region} --association-id ${aws_ssm_association.bootstrap_complete.id} --query 'AssociationExecutions[].{ExecutionId:ExecutionId,Status:Status,DetailedStatus:DetailedStatus}' --output table"
  description = "Command that lists custom bootstrap document executions for the completion Association"
}
