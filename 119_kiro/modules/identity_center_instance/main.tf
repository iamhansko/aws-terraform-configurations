# The decision is intentionally sticky in Terraform state. If no instance exists on the first plan, this
# module creates and continues to own one even though subsequent discovery naturally sees that new instance.
# Without ignore_changes, a count based directly on the discovery result would remove its own resource on
# the next plan. If an instance exists initially, it remains external and is never imported or destroyed.
resource "terraform_data" "creation_decision" {
  input = var.existing_instance_arn == null

  lifecycle {
    ignore_changes = [input]
  }
}

resource "awscc_sso_instance" "identity_center" {
  count = terraform_data.creation_decision.input ? 1 : 0
}

locals {
  instance_arn      = terraform_data.creation_decision.input ? one(awscc_sso_instance.identity_center[*].instance_arn) : var.existing_instance_arn
  identity_store_id = terraform_data.creation_decision.input ? one(awscc_sso_instance.identity_center[*].identity_store_id) : var.existing_identity_store_id
}
