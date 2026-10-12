# The CSI snapshot controller, as an EKS managed addon like every other addon here
# (rules.md C-4).
#
# This replaces two lines of the _monolithic bootstrap that were the worst-behaved thing in the
# whole template:
#
#   kubectl kustomize https://github.com/kubernetes-csi/external-snapshotter/client/config/crd | kubectl create -f -
#   kubectl -n kube-system kustomize https://github.com/kubernetes-csi/external-snapshotter/deploy/kubernetes/snapshot-controller | kubectl create -f -
#
# Three problems with that, all of which this addon removes. Neither URL carries a ref, so both
# tracked the upstream default branch - the VolumeSnapshot CRD schema the cluster got depended on
# the day the stack was created. Both used "kubectl create" rather than "apply", so a second run
# failed with AlreadyExists and took the rest of the bootstrap with it. And neither was in
# Terraform state, so the CRDs survived terraform destroy while the workloads that used them did
# not.
#
# Worth being clear about what this controller is for, because it is easy to assume the EBS CSI
# driver covers it. The driver creates and attaches volumes; the snapshot controller is what turns
# a VolumeSnapshot object into a driver call and watches it to completion. Velero's CSI support
# takes snapshots through those objects, so without this controller a backup with
# --snapshot-move-data produces VolumeSnapshots that sit Pending forever and a backup that reports
# PartiallyFailed with no volume data in it.
resource "aws_eks_addon" "snapshot_controller" {
  cluster_name  = var.cluster_name
  addon_name    = "snapshot-controller"
  addon_version = var.addon_version
  # No service_account_role_arn and no pod_identity_association: the controller only talks to the
  # Kubernetes API, and the AWS-side work is done by the EBS CSI driver, which has its own
  # credentials.
  resolve_conflicts_on_create = var.resolve_conflicts_on_create
  resolve_conflicts_on_update = var.resolve_conflicts_on_update
}
