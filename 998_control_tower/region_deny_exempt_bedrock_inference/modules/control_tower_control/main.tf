# Enables one Control Tower control on one OU. Kept to a single control so its
# arn/id outputs stay unambiguous; a root needing several can instantiate this
# module more than once, the way a project with two node groups instantiates a
# node group module twice.
#
# Two things this resource does not express, and the caller has to arrange:
#
#   1. The landing zone must already be set up. target_identifier only creates a
#      dependency on the OU, so the root has to order this module after the
#      landing zone module with depends_on (rules.md D-2).
#   2. The OU must be registered with Control Tower. Enabling a control on an OU
#      Control Tower does not govern fails with a ValidationException.
resource "aws_controltower_control" "control_tower_control" {
  control_identifier = var.control_identifier
  target_identifier  = var.target_identifier

  # Parameter values are JSON documents, which is why they arrive as strings that
  # the caller has already run through jsonencode: AllowedRegions and
  # ExemptedActions take arrays, other controls take scalars, and a single
  # well-typed Terraform variable cannot cover both.
  dynamic "parameters" {
    for_each = var.parameters
    content {
      key   = parameters.key
      value = parameters.value
    }
  }
}
