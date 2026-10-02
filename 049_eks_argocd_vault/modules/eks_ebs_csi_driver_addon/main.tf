# The EBS CSI driver, as its own module like every other EKS addon (rules.md C-4).
#
# Why this project needs it: the Sentry chart brings PostgreSQL, Redis, Kafka, ZooKeeper and
# ClickHouse, all of which want PersistentVolumeClaims. Since Kubernetes 1.23 the in-tree EBS
# provisioner is gone, so without this addon the cluster's gp2 StorageClass has nothing
# behind it and every one of those claims stays Pending. The Helm release then sits waiting
# on pods that will never be Ready until its timeout expires - which is why the Sentry
# release's timeout is measured in tens of minutes and why this addon has to exist first.
#
# The IAM role lives here rather than in the root because it is not reusable: its trust
# policy names the exact namespace and service account this addon creates, and the addon
# needs an ARN only this role can provide. That is one component, the same reasoning that
# keeps an IRSA role next to its Helm release (rules.md C-2).
resource "aws_iam_role" "ebs_csi_driver" {
  name = var.role_name
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Federated = var.oidc_provider_arn }
      Action    = "sts:AssumeRoleWithWebIdentity"
      Condition = {
        StringEquals = {
          # Restricts the role to exactly one pod identity. Without the sub condition any
          # service account with a projected token from this issuer could assume it.
          "${var.oidc_issuer_host}:sub" = "system:serviceaccount:${var.namespace}:${var.service_account_name}"
          "${var.oidc_issuer_host}:aud" = "sts.amazonaws.com"
        }
      }
    }]
  })
}
# for_each rather than one attachment per policy, so the list can be extended by a caller
# without editing this module (rules.md B-7). toset is safe here because these are literal
# ARNs, known at plan time - the same pattern would fail on IDs coming out of another module
# (rules.md B-8).
resource "aws_iam_role_policy_attachment" "ebs_csi_driver" {
  for_each   = toset(var.iam_policy_arns)
  role       = aws_iam_role.ebs_csi_driver.name
  policy_arn = each.value
}
resource "aws_eks_addon" "ebs_csi_driver" {
  cluster_name  = var.cluster_name
  addon_name    = "aws-ebs-csi-driver"
  addon_version = var.addon_version
  # This is what wires IRSA up: EKS annotates the service account it creates with this ARN.
  # Doing it here rather than patching the service account afterwards is the whole reason the
  # role and the addon belong in one module.
  service_account_role_arn    = aws_iam_role.ebs_csi_driver.arn
  resolve_conflicts_on_create = var.resolve_conflicts_on_create
  resolve_conflicts_on_update = var.resolve_conflicts_on_update

  # The policies have to be attached before the controller starts provisioning volumes, and
  # the attachments are not referenced by anything above - only the role itself is - so
  # nothing else orders them (rules.md D-1).
  depends_on = [aws_iam_role_policy_attachment.ebs_csi_driver]
}
