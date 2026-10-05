# The EBS CSI driver, as its own module like every other EKS addon (rules.md C-4).
#
# Why this project needs it, and only on the parent cluster: Karmada's etcd is a StatefulSet with a
# volumeClaimTemplate, and the guidance installer ran `kubectl karmada init --etcd-storage-mode PVC
# --storage-classes-name ebs-sc` to put it on an EBS volume rather than on a node's local disk. Since
# Kubernetes 1.23 the in-tree EBS provisioner is gone, so without this addon that claim stays Pending, the
# etcd pod never starts, and every other Karmada component sits in its wait-for-etcd init container. The
# failure reads as "Karmada did not come up" rather than "no volume was provisioned", which is why the
# addon is wired explicitly instead of being assumed.
#
# The member clusters do not get it. Nothing on them claims a volume - the agent is a single stateless
# Deployment - and the guidance installer deployed the addon only on the parent for the same reason.
#
# The IAM role lives here rather than in the root because it is not reusable: it exists for exactly one
# service account in one namespace, and the addon needs an ARN only this role can provide. That is one
# component, the same reasoning that keeps a controller's role next to its Helm release (rules.md C-2).
#
# EKS Pod Identity rather than IRSA. The guidance installer used IRSA - it ran `eksctl create
# iamserviceaccount --role-only` against the cluster's OIDC provider and then named the resulting role in
# `eksctl create addon --service-account-role-arn`, with the role named
# AmazonEKS_EBS_CSI_DriverRole_<region>_<prefix> so that one role could be shared. Pod Identity reaches the
# same place with less: the association names the cluster rather than its OIDC issuer, so the trust policy
# has nothing cluster-specific in it, and there is no annotation to patch onto the service account
# afterwards.
resource "aws_iam_role" "ebs_csi_driver" {
  name        = var.role_name
  name_prefix = var.role_name == null ? var.role_name_prefix : null
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = {
        # pods.eks.amazonaws.com, not ec2.amazonaws.com and not the cluster's OIDC provider. This is the Pod
        # Identity trust: the agent on the node exchanges a service account token for credentials from this
        # role, and which service account may do so is decided by the pod_identity_association below rather
        # than by a condition here.
        Service = "pods.eks.amazonaws.com"
      }
      # TagSession as well as AssumeRole. Pod Identity attaches session tags naming the cluster, namespace
      # and service account, and without this action the exchange fails - with an error about tagging rather
      # than about trust, which is not where anyone looks first.
      Action = ["sts:AssumeRole", "sts:TagSession"]
    }]
  })
}
# for_each rather than one attachment per policy, so the list can be extended by a caller without editing
# this module (rules.md B-7). toset is safe here because these are literal ARNs, known at plan time - the
# same pattern would fail on IDs coming out of another module (rules.md B-8).
resource "aws_iam_role_policy_attachment" "ebs_csi_driver" {
  for_each   = toset(var.iam_policy_arns)
  role       = aws_iam_role.ebs_csi_driver.name
  policy_arn = each.value
}
resource "aws_eks_addon" "ebs_csi_driver" {
  cluster_name                = var.cluster_name
  addon_name                  = "aws-ebs-csi-driver"
  addon_version               = var.addon_version
  resolve_conflicts_on_create = var.resolve_conflicts_on_create
  resolve_conflicts_on_update = var.resolve_conflicts_on_update
  # This is the whole of the Pod Identity wiring, and it is what makes the role above usable. EKS creates
  # the association for the service account the addon runs as, so there is no annotation to patch onto the
  # service account afterwards - which is why the role and the addon belong in one module.
  pod_identity_association {
    role_arn        = aws_iam_role.ebs_csi_driver.arn
    service_account = var.service_account_name
  }
  # The policies have to be attached before the controller starts provisioning volumes, and the attachments
  # are not referenced by anything above - only the role itself is - so nothing else orders them
  # (rules.md D-1).
  depends_on = [aws_iam_role_policy_attachment.ebs_csi_driver]
}
