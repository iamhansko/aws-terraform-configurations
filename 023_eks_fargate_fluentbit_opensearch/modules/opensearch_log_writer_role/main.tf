# Fine-grained access control is a second, independent authorization layer that
# lives inside the domain, and it is the half the _monolithic template did not
# express in infrastructure at all - it shipped src/client.py for a human to run
# against a live domain. A request from Fluent Bit has to clear both layers:
#
#   1. IAM      - the pod execution role needs es:ESHttp* on the domain, granted
#                 by the inline policy in modules/fargate_fluentbit_logging.
#   2. FGAC     - the signing role has to be mapped to an OpenSearch role that
#                 permits the action, which is what this module declares.
#
# Passing layer 1 and failing layer 2 is the failure this module exists to
# prevent, and it is a quiet one: the domain answers 403 to every bulk request,
# nothing appears in the domain's own logs by default, and both the delivery
# pipeline and the IAM policy look correct from the AWS side. The only visible
# symptom is an index that never gets created.
#
# The role and its mapping are one module rather than two because a mapping is
# meaningless without the role it names, and this role has no use beyond being
# mapped (rules.md C-2). The module is handed ARNs and never learns that they
# belong to a Fargate pod execution role (rules.md B-6).
resource "opensearch_role" "log_writer" {
  role_name           = var.role_name
  description         = "Write-only access to the log indices, for the Fargate Fluent Bit log router"
  cluster_permissions = var.cluster_permissions

  index_permissions {
    index_patterns  = var.index_patterns
    allowed_actions = var.allowed_index_actions
  }
}
resource "opensearch_roles_mapping" "log_writer" {
  role_name     = opensearch_role.log_writer.role_name
  description   = "Maps the log shipper's signing identity onto ${var.role_name}"
  backend_roles = var.backend_role_arns
  users         = var.mapped_users

  # role_name above is a resource reference, so the role is already ordered
  # first. Stated anyway because the security plugin accepts a mapping for a role
  # that does not exist and silently grants nothing - so an ordering mistake here
  # would not surface as an apply error (rules.md D-1).
  depends_on = [opensearch_role.log_writer]
}
