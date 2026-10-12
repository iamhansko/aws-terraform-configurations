data "aws_caller_identity" "current" {}
data "aws_region" "current" {}
# The wrong-account guard (rules.md I-2). Fails the plan, before the role exists anywhere.
resource "terraform_data" "account_guard" {
  lifecycle {
    precondition {
      condition     = data.aws_caller_identity.current.account_id == var.stack_account_id
      error_message = "This root must be applied with credentials for stack_account_id. In the bucket account the create-stack command would succeed without crossing an account boundary and demonstrate nothing."
    }
  }
}
module "cloudformation_service_role" {
  source = "./modules/cloudformation_service_role"

  name = var.cloudformation_role_name

  depends_on = [terraform_data.account_guard]
}
