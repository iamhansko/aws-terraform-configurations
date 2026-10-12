data "aws_caller_identity" "current" {}
# The wrong-account guard (rules.md I-2). The caller identity is known at plan, so this fails the plan before
# anything is created rather than failing a resource halfway through an apply.
#
# On a terraform_data at the root rather than inside the module, because only this root knows which account
# it is meant for - the module just creates a bucket wherever it is pointed.
resource "terraform_data" "account_guard" {
  lifecycle {
    precondition {
      condition     = data.aws_caller_identity.current.account_id == var.bucket_account_id
      error_message = "This root must be applied with credentials for bucket_account_id. Applied in the stack account it creates the bucket there, and the mistake surfaces only later, as a bucket policy granting an account access to itself."
    }
  }
}
module "template_bucket" {
  source = "./modules/cross_account_template_bucket"

  reader_account_ids = [var.stack_account_id]
  template_key       = var.template_key
  template_body      = file("${path.root}/${var.template_path}")

  # Nothing is created until the guard has passed.
  depends_on = [terraform_data.account_guard]
}
