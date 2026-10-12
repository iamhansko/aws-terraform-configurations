data "aws_caller_identity" "current" {}
data "aws_partition" "current" {}
data "aws_region" "current" {}

resource "terraform_data" "account_guard" {
  input = var.target_account_id

  lifecycle {
    precondition {
      condition     = data.aws_caller_identity.current.account_id == var.target_account_id
      error_message = "This root must be planned and applied with target_account_id credentials. The active caller belongs to a different AWS account."
    }
  }
}

module "codecommit_replication_target" {
  source = "./modules/codecommit_replication_target"

  partition                  = data.aws_partition.current.partition
  target_account_id          = var.target_account_id
  source_account_id          = var.source_account_id
  target_account_repository  = var.target_account_repository
  cross_account_role_name    = var.cross_account_role_name
  source_codebuild_role_name = var.source_codebuild_role_name

  depends_on = [terraform_data.account_guard]
}
