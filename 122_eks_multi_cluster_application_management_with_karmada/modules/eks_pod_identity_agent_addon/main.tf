# eks-pod-identity-agent is the newer alternative to IRSA: pods get AWS
# credentials from a node-local agent through an EKS Pod Identity association,
# with no OIDC trust policy to maintain. The guidance installer this project replaces had no equivalent: it
# ran `eksctl utils associate-iam-oidc-provider` and `eksctl create iamserviceaccount` to set up IRSA for
# the EBS CSI driver instead. This addon is what lets that driver's role be a Pod Identity role here, so it
# is only installed on the cluster that runs the driver.
#
# It runs as a DaemonSet, so it reaches ACTIVE with zero nodes and only needs
# the cluster to exist. Own module per addon (rules.md C-4), which also means
# switching this project's controllers from IRSA to Pod Identity later touches
# only the controller modules, not this one.
resource "aws_eks_addon" "pod_identity_agent" {
  cluster_name                = var.cluster_name
  addon_name                  = "eks-pod-identity-agent"
  addon_version               = var.addon_version
  resolve_conflicts_on_create = var.resolve_conflicts_on_create
  resolve_conflicts_on_update = var.resolve_conflicts_on_update
}
