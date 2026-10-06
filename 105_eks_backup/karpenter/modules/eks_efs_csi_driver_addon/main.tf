# The aws-efs-csi-driver addon and the IAM role its controller assumes through
# IRSA live in one module: aws_eks_addon.service_account_role_arn references the
# role directly, so splitting them would only add an ARN round trip through root
# variables for two resources that cannot exist apart (rules.md C-2). Own module
# per addon, as with vpc-cni/kube-proxy/coredns (rules.md C-4).
#
# This replaces the _monolithic design's manifests/efs-csi-controller.yaml, a
# vendored copy of the driver's Deployment that the operator applied by hand and
# that nothing then tracked or upgraded (rules.md E-1).
resource "aws_iam_role" "efs_csi_driver_iam_role" {
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = {
        Federated = var.oidc_provider_arn
      }
      Action = "sts:AssumeRoleWithWebIdentity"
      Condition = {
        StringEquals = {
          "${var.oidc_issuer_host}:sub" = "system:serviceaccount:${var.namespace}:${var.service_account_name}"
          "${var.oidc_issuer_host}:aud" = "sts.amazonaws.com"
        }
      }
    }]
  })
}
resource "aws_iam_role_policy_attachment" "efs_csi_driver_iam_role" {
  for_each   = toset(var.iam_policy_arns)
  role       = aws_iam_role.efs_csi_driver_iam_role.name
  policy_arn = each.value
}
# The caller's configuration_values with the controller tolerations merged into it, encoded once.
# Merged rather than either one winning, so setting one does not silently discard the other. Omitted
# entirely when both are empty: an explicit null is rejected by the addon's JSON schema, while an
# absent key leaves EKS to apply its own defaults (rules.md E-5).
locals {
  caller_configuration = var.configuration_values == null ? {} : jsondecode(var.configuration_values)
  controller_configuration = merge(
    try(local.caller_configuration.controller, {}),
    length(var.controller_tolerations) > 0 ? { tolerations = var.controller_tolerations } : {},
    length(var.controller_pod_annotations) > 0 ? { podAnnotations = var.controller_pod_annotations } : {},
  )
  configuration = length(local.controller_configuration) > 0 ? merge(
    local.caller_configuration,
    { controller = local.controller_configuration },
  ) : local.caller_configuration
  configuration_values = length(local.configuration) > 0 ? jsonencode(local.configuration) : null
}

resource "aws_eks_addon" "efs_csi_driver" {
  cluster_name                = var.cluster_name
  addon_name                  = "aws-efs-csi-driver"
  addon_version               = var.addon_version
  service_account_role_arn    = aws_iam_role.efs_csi_driver_iam_role.arn
  resolve_conflicts_on_create = var.resolve_conflicts_on_create
  resolve_conflicts_on_update = var.resolve_conflicts_on_update
  configuration_values        = local.configuration_values
  # The role must already carry AmazonEFSCSIDriverPolicy before the controller
  # pod starts creating access points, and service_account_role_arn alone
  # doesn't order this resource after the attachments (rules.md D-1).
  depends_on = [aws_iam_role_policy_attachment.efs_csi_driver_iam_role]
}
