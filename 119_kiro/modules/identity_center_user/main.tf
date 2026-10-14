# The IAM Identity Center user the Kiro subscription is attached to.
#
# A Terraform resource rather than the `aws identitystore create-user` the _monolithic template ran from the
# instance's userdata. That call left the user outside every state: destroying the stack kept it, and
# re-creating the stack failed at the same call with a ConflictException because the user name was taken.
# Here terraform destroy deletes it, and its ID is known before the instance boots, so the bootstrap script
# is handed it instead of discovering it.
resource "aws_identitystore_user" "user" {
  identity_store_id = var.identity_store_id
  user_name         = var.user_name
  display_name      = var.display_name
  name {
    given_name  = var.given_name
    family_name = var.family_name
  }
  emails {
    value   = var.email
    type    = "work"
    primary = true
  }
}
