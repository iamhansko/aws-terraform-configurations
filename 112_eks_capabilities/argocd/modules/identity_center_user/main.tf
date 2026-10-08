# A user in the IAM Identity Center identity store, so the Argo CD capability has an identity to map
# to its ADMIN role. Argo CD here does not support local users at all - Identity Center is the only
# way in - so without at least one identity the UI is unreachable by anyone.
#
# The _monolithic template did this with a CloudFormation custom resource and a Lambda function, and
# none of it could have worked:
#
#   - The function's source file was not Python. It was the literal text of a CloudFormation
#     intrinsic, {'Fn::Sub': 'import json\n...'}, written to disk unresolved by the converter.
#   - The code imported cfnresponse, a module CloudFormation injects only into inline Lambda source.
#     A zipped function fails while loading it, before the handler runs.
#   - It substituted ${IamIdentityCenterInstance.IdentityStoreId}, a reference to a resource that
#     does not exist anywhere in the template.
#
# aws_identitystore_user replaces all of it: one resource, whose id is an attribute rather than a
# value parsed out of a Lambda's JSON response, and which Terraform deletes on destroy - something
# the original's Delete branch explicitly did not do.
resource "aws_identitystore_user" "user" {
  identity_store_id = var.identity_store_id

  user_name    = var.user_name
  display_name = var.display_name

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
