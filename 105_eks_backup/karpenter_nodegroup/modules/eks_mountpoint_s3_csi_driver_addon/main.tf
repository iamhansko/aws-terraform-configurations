# The aws-mountpoint-s3-csi-driver addon, the IAM role its pods assume through
# IRSA, and the customer managed policy that role carries live in one module:
# aws_eks_addon.service_account_role_arn references the role directly, so
# splitting them would only add an ARN round trip through root variables for
# resources that cannot exist apart (rules.md C-2). Own module per addon, as
# with vpc-cni/kube-proxy/coredns (rules.md C-4).
resource "aws_iam_role" "mountpoint_s3_csi_driver_iam_role" {
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
# There is no AWS managed policy for this driver, so unlike the EBS and EFS
# addons the permissions are written here - and scoped to the buckets the caller
# named rather than to every bucket in the account.
resource "aws_iam_policy" "mountpoint_s3_csi_driver_policy" {
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        # Mountpoint lists the bucket to resolve directory listings, which is a
        # bucket-level action and so takes the bucket ARN without a key suffix.
        Effect   = "Allow"
        Action   = ["s3:ListBucket"]
        Resource = var.bucket_arns
      },
      {
        # Object-level actions take the /* form. DeleteObject is only included
        # when allow_delete is set, so a read-mostly mount cannot remove data
        # even if someone adds the allow-delete mount option later.
        Effect = "Allow"
        Action = concat(
          ["s3:GetObject", "s3:PutObject", "s3:AbortMultipartUpload"],
          var.allow_delete ? ["s3:DeleteObject"] : [],
        )
        Resource = [for arn in var.bucket_arns : "${arn}/*"]
      },
    ]
  })
}
resource "aws_iam_role_policy_attachment" "mountpoint_s3_csi_driver_iam_role" {
  role       = aws_iam_role.mountpoint_s3_csi_driver_iam_role.name
  policy_arn = aws_iam_policy.mountpoint_s3_csi_driver_policy.arn
}
# The caller's configuration_values with the controller tolerations merged into it, encoded once.
# Merged rather than either one winning, so setting one does not silently discard the other. Omitted
# entirely when both are empty: an explicit null is rejected by the addon's JSON schema, while an
# absent key leaves EKS to apply its own defaults (rules.md E-5).
locals {
  caller_configuration = var.configuration_values == null ? {} : jsondecode(var.configuration_values)
  configuration = length(var.controller_tolerations) > 0 ? merge(
    local.caller_configuration,
    {
      controller = merge(
        try(local.caller_configuration.controller, {}),
        { tolerations = var.controller_tolerations },
      )
    },
  ) : local.caller_configuration
  configuration_values = length(local.configuration) > 0 ? jsonencode(local.configuration) : null
}

resource "aws_eks_addon" "mountpoint_s3_csi_driver" {
  cluster_name                = var.cluster_name
  addon_name                  = "aws-mountpoint-s3-csi-driver"
  addon_version               = var.addon_version
  service_account_role_arn    = aws_iam_role.mountpoint_s3_csi_driver_iam_role.arn
  resolve_conflicts_on_create = var.resolve_conflicts_on_create
  resolve_conflicts_on_update = var.resolve_conflicts_on_update
  configuration_values        = local.configuration_values
  # The role must already carry the bucket policy before the driver mounts
  # anything, and service_account_role_arn alone doesn't order this resource
  # after the attachment (rules.md D-1).
  depends_on = [aws_iam_role_policy_attachment.mountpoint_s3_csi_driver_iam_role]
}
