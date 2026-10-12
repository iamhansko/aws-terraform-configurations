# The EBS CSI driver, as its own module like every other EKS addon (rules.md C-4).
#
# The blueprint installed it through eks-blueprints-addons with an IRSA role from the
# iam-role-for-service-accounts-eks module, and nothing in the blueprint itself claims a volume - it
# is there so that a workload that asks for a PersistentVolumeClaim gets one. Since Kubernetes 1.23
# the in-tree EBS provisioner is gone, and without this addon such a claim stays Pending with no
# error anywhere but the claim's own events.
#
# The IAM role lives here rather than in the root because it exists for exactly one service account
# in one namespace, and the addon needs an ARN only this role can provide. That is one component,
# the same reasoning that keeps a controller's role next to its Helm release (rules.md C-2).
#
# IRSA, as the blueprint had it, rather than EKS Pod Identity. The cluster already has an OIDC
# provider for the EMR job role and the cluster autoscaler, both of which are IRSA as well - EMR on
# EKS creates its own service accounts per job and does not create Pod Identity associations for
# them - so Pod Identity here would add the eks-pod-identity-agent addon for this one role.
resource "aws_iam_role" "ebs_csi_driver" {
  name        = var.role_name
  name_prefix = var.role_name == null ? var.role_name_prefix : null

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
          # The one service account the addon's controller runs as. The node DaemonSet runs as a
          # different one and makes no AWS calls, so it is not named.
          "${var.oidc_issuer_host}:sub" = "system:serviceaccount:kube-system:${var.service_account_name}"
          "${var.oidc_issuer_host}:aud" = "sts.amazonaws.com"
        }
      }
    }]
  })
}
# for_each rather than one attachment per policy, so the list can be extended by a caller without
# editing this module (rules.md B-7). toset is safe here because these are literal ARNs, known at
# plan time - the same pattern would fail on IDs coming out of another module (rules.md B-8).
resource "aws_iam_role_policy_attachment" "ebs_csi_driver" {
  for_each   = toset(var.iam_policy_arns)
  role       = aws_iam_role.ebs_csi_driver.name
  policy_arn = each.value
}
# ec2:CreateTags on volumes and snapshots the driver itself just created, scoped by the
# ec2:CreateAction condition. Off by default in this project, which takes no snapshots - it is here
# so a caller that adds a snapshot workflow later does not have to widen the managed policy.
resource "aws_iam_role_policy" "ebs_csi_driver_snapshot_tagging" {
  count = var.grant_snapshot_tagging ? 1 : 0

  name = "snapshot-tagging"
  role = aws_iam_role.ebs_csi_driver.name
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Action = ["ec2:CreateTags"]
      Resource = [
        "arn:aws:ec2:*:*:volume/*",
        "arn:aws:ec2:*:*:snapshot/*",
      ]
      Condition = {
        StringEquals = {
          # Only on resources the driver itself just created. Without the condition this is
          # permission to retag any volume or snapshot in the account.
          "ec2:CreateAction" = ["CreateVolume", "CreateSnapshot"]
        }
      }
    }]
  })
}
resource "aws_eks_addon" "ebs_csi_driver" {
  cluster_name                = var.cluster_name
  addon_name                  = "aws-ebs-csi-driver"
  addon_version               = var.addon_version
  resolve_conflicts_on_create = var.resolve_conflicts_on_create
  resolve_conflicts_on_update = var.resolve_conflicts_on_update

  # The whole of the IRSA wiring on the addon side: EKS writes this ARN into the
  # eks.amazonaws.com/role-arn annotation of the controller's service account, so there is nothing
  # to patch afterwards - which is why the role and the addon belong in one module.
  service_account_role_arn = aws_iam_role.ebs_csi_driver.arn

  # The policies have to be attached before the controller starts provisioning volumes, and the
  # attachments are not referenced by anything above - only the role itself is - so nothing else
  # orders them (rules.md D-1).
  depends_on = [
    aws_iam_role_policy_attachment.ebs_csi_driver,
    aws_iam_role_policy.ebs_csi_driver_snapshot_tagging,
  ]
}
