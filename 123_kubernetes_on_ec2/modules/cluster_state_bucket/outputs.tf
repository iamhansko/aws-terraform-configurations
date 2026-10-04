output "bucket_name" {
  value       = aws_s3_bucket.cluster_state.id
  description = "Name of the handoff bucket, which every instance's user data interpolates into an aws s3 command"
}

output "bucket_arn" {
  value       = aws_s3_bucket.cluster_state.arn
  description = "ARN of the handoff bucket"
}

output "access_policy_arn" {
  value       = aws_iam_policy.cluster_state_access.arn
  description = "ARN of the policy granting read and write on the handoff objects. Attached by the caller to each instance role, keyed by a label rather than iterated as a list because this value is unknown until apply (rules.md B-8)"
}

output "object_keys" {
  value       = var.object_keys
  description = "Object keys the policy grants on, re-exposed so the user data that reads and writes them does not restate the names (rules.md B-5)"
}

output "kubeconfig_object_uri" {
  value       = "s3://${aws_s3_bucket.cluster_state.id}/kubeconfig"
  description = "S3 URI of the admin kubeconfig the control plane uploads and the workbench downloads"
}

output "join_command_object_uri" {
  value       = "s3://${aws_s3_bucket.cluster_state.id}/join.sh"
  description = "S3 URI of the kubeadm join command the control plane uploads and the worker downloads"
}

output "objects_check_command" {
  value       = "aws s3 ls s3://${aws_s3_bucket.cluster_state.id}/"
  description = "Command that lists the handoff objects. Both present means the control plane finished kubeadm init; neither means it did not, which is the first thing to check when the worker never joins"
}
