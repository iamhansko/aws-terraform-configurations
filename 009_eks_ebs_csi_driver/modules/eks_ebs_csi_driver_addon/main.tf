# The aws-ebs-csi-driver addon and the IAM role its controller assumes through
# IRSA live in one module: aws_eks_addon.service_account_role_arn references
# the role directly, so splitting them would only add an ARN round trip
# through root variables for two resources that cannot exist apart
# (rules.md C-2). Own module per addon, as with vpc-cni/kube-proxy/coredns
# (rules.md C-4).
resource "aws_iam_role" "ebs_csi_driver_iam_role" {
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
resource "aws_iam_role_policy_attachment" "ebs_csi_driver_iam_role" {
  for_each   = toset(var.iam_policy_arns)
  role       = aws_iam_role.ebs_csi_driver_iam_role.name
  policy_arn = each.value
}
resource "aws_eks_addon" "ebs_csi_driver" {
  cluster_name                = var.cluster_name
  addon_name                  = "aws-ebs-csi-driver"
  addon_version               = var.addon_version
  service_account_role_arn    = aws_iam_role.ebs_csi_driver_iam_role.arn
  resolve_conflicts_on_create = var.resolve_conflicts_on_create
  resolve_conflicts_on_update = var.resolve_conflicts_on_update
  configuration_values = jsonencode({
    controller = {
      replicaCount = var.controller_replica_count
    }
  })
  # The role must already carry AmazonEBSCSIDriverPolicy before the controller
  # pod starts calling EC2, and service_account_role_arn alone doesn't order
  # this resource after the attachments (rules.md D-1).
  depends_on = [aws_iam_role_policy_attachment.ebs_csi_driver_iam_role]
}
