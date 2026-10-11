# The EBS CSI driver, as its own module like every other EKS addon (rules.md C-4).
#
# Why this project needs it: the demo pod's MySQL container writes to a PersistentVolumeClaim.
# Since Kubernetes 1.23 the in-tree EBS provisioner is gone, so without this addon nothing answers
# that claim - it stays Pending, the pod is never scheduled, the Service has no endpoint, and the
# Ingress that this project is actually about returns 503 from a controller that is working
# perfectly. Three layers away from the cause.
#
# The IAM role lives here rather than in the root because it is not reusable: it exists for exactly
# one service account in one namespace, and the addon needs an ARN only this role can provide. That
# is one component, the same reasoning that keeps a controller's role next to its Helm release
# (rules.md C-2).
#
# EKS Pod Identity rather than the IRSA role the _monolithic template built. The two are
# equivalent in what the driver can do; Pod Identity's trust policy names no cluster and no OIDC
# issuer, so the role has nothing in it that has to be rebuilt when the cluster is replaced - and
# there is no service account annotation to patch after the addon installs, which is the step the
# original had to get right by hand. It does require the eks-pod-identity-agent addon on the
# cluster, which is its own module and has to exist first (rules.md C-4/D-2).
resource "aws_iam_role" "ebs_csi_driver" {
  name        = var.role_name
  name_prefix = var.role_name == null ? var.role_name_prefix : null

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = {
        # pods.eks.amazonaws.com, not ec2.amazonaws.com and not the cluster's OIDC provider. This
        # is the Pod Identity trust: the agent on the node exchanges a service account token for
        # credentials from this role, and which service account may do so is decided by the
        # aws_eks_pod_identity_association below rather than by a condition here.
        Service = "pods.eks.amazonaws.com"
      }
      # TagSession as well as AssumeRole. Pod Identity attaches session tags naming the cluster,
      # namespace and service account, and without this action the exchange fails - with an error
      # about tagging rather than about trust, which is not where anyone looks first.
      Action = ["sts:AssumeRole", "sts:TagSession"]
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

  # This is the whole of the Pod Identity wiring, and it is what makes the role above usable. EKS
  # creates the association for the service account the addon runs as, so there is no annotation to
  # patch onto the service account afterwards - which is why the role and the addon belong in one
  # module.
  pod_identity_association {
    role_arn        = aws_iam_role.ebs_csi_driver.arn
    service_account = var.service_account_name
  }

  # The policies have to be attached before the controller starts provisioning volumes, and the
  # attachments are not referenced by anything above - only the role itself is - so nothing else
  # orders them (rules.md D-1).
  depends_on = [
    aws_iam_role_policy_attachment.ebs_csi_driver,
    aws_iam_role_policy.ebs_csi_driver_snapshot_tagging,
  ]
}
