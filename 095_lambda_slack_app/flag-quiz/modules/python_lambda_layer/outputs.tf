output "layer_version_arn" {
  value       = aws_lambda_layer_version.layer.arn
  description = "ARN of the published layer version, which the functions name"
}
output "packages" {
  value       = local.build.packages
  description = "Every distribution in the layer, as the builder read it back after pip install - the requirements and everything they pulled in"
}
output "package_s3_uri" {
  value       = "s3://${local.build.bucket}/${local.build.key}"
  description = "Where the builder uploaded the package"
}
output "build_log_command" {
  value       = "aws logs tail ${aws_cloudwatch_log_group.builder.name} --since 1h"
  description = "The builder's log, where a failed pip install is recorded in full"
}
