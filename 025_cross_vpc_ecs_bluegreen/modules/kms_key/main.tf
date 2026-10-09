# The one customer managed key in this project. Four things use it, and it is worth listing them
# because the key policy question below depends on which:
#
#   Secrets Manager   encrypts the database credential secret
#   Aurora            storage_encrypted and the Performance Insights store
#   ECR               the red repository, which the _monolithic template set to KMS while leaving
#                     the green one on AES256 - that asymmetry is deliberate in the original and
#                     is one of the few things the two application stacks genuinely differ by
#   ECS               managed storage, which is the one that needs more than the default policy
#
# No explicit key policy, so the key keeps the provider default: the account root can administer
# it and IAM policies decide everything else. That is enough for the first three - Secrets
# Manager, RDS and ECR all act with the caller's or a grant's credentials, and the ECS task
# execution role's kms:Decrypt is granted in its own IAM policy.
#
# It is not enough for ECS managed storage, which is why the cluster module defaults that off. See
# the comment on managed_storage_kms_key_id in modules/ecs_cluster_capacity/variables.tf.
resource "aws_kms_key" "kms_key" {
  description                        = var.description
  is_enabled                         = true
  enable_key_rotation                = var.enable_key_rotation
  rotation_period_in_days            = var.rotation_period_in_days
  deletion_window_in_days            = var.deletion_window_in_days
  customer_master_key_spec           = "SYMMETRIC_DEFAULT"
  key_usage                          = "ENCRYPT_DECRYPT"
  bypass_policy_lockout_safety_check = false
}
resource "aws_kms_alias" "kms_key_alias" {
  name          = var.alias_name
  target_key_id = aws_kms_key.kms_key.id
}
