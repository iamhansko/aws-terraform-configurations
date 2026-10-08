# One IAM role per tenant, each mapped into the cluster with access to exactly one namespace.
#
# This is the IAM half of soft multi-tenancy, and the three resources per tenant are one mechanism: the role is
# the identity, the access entry makes the cluster aware of it, and the policy association is what limits it to
# a namespace. An entry without an association is a principal the cluster knows and grants nothing to; an
# association without an entry is rejected (rules.md C-2/D-1).
#
# for_each over a map of labels rather than a resource per tenant, which is what the _monolithic template had -
# tenant_a_role and tenant_b_role declared twice over, with their access entries and associations duplicated
# alongside. Adding a third tenant there meant six more resources copied by hand (rules.md B-7).
resource "aws_iam_role" "tenant" {
  for_each = var.tenants

  name                 = "${var.role_name_prefix}-${each.key}"
  description          = "Assumed to act as tenant ${each.key}, which may edit the ${each.value} namespace and nothing else"
  max_session_duration = var.session_duration

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { AWS = var.trusted_principal_arns }
      Action    = "sts:AssumeRole"
    }]
  })
}
# The role has no AWS permissions of its own, and that is deliberate: a tenant here is a Kubernetes identity
# rather than an AWS one. Everything it can do is granted by the access policy association below, inside the
# cluster. The _monolithic template attached nothing either - worth stating so it reads as a decision rather
# than an omission.
resource "aws_eks_access_entry" "tenant" {
  for_each = var.tenants

  cluster_name  = var.cluster_name
  principal_arn = aws_iam_role.tenant[each.key].arn
  type          = "STANDARD"
  # The Kubernetes username the role maps to. Named after the tenant so an audit log entry or an RBAC error
  # says which tenant it was, rather than showing a generated ARN-derived name.
  user_name = "tenant-${each.key}"
}
resource "aws_eks_access_policy_association" "tenant" {
  for_each = var.tenants

  cluster_name  = var.cluster_name
  principal_arn = aws_iam_role.tenant[each.key].arn
  policy_arn    = var.access_policy_arn

  access_scope {
    # namespace, not cluster. This one line is the isolation being demonstrated: the same policy at cluster
    # scope would let either tenant read the other's Secrets.
    type       = "namespace"
    namespaces = [each.value]
  }

  # The association names the same principal as the entry but does not reference it, so nothing orders the two
  # (rules.md D-1). The _monolithic template had exactly this gap - its associations and entries were unrelated
  # resources, and an association applied first fails with ResourceNotFoundException.
  depends_on = [aws_eks_access_entry.tenant]
}
