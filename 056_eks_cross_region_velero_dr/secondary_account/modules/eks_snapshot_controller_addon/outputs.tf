output "snapshot_controller_addon_arn" {
  value       = aws_eks_addon.snapshot_controller.arn
  description = "ARN of the snapshot-controller addon. aws_eks_addon exposes no status attribute, so this is the only thing worth taking as an output (rules.md E-5)"
}
output "snapshot_controller_addon_version" {
  value       = aws_eks_addon.snapshot_controller.addon_version
  description = "The version EKS actually installed, which is the resolved default when addon_version was left null. Worth reading once: it decides the VolumeSnapshot CRD schema the cluster has"
}
output "snapshot_check_command" {
  value       = "kubectl get volumesnapshot,volumesnapshotcontent --all-namespaces"
  description = "Every snapshot object and the driver-side content backing it. A VolumeSnapshot stuck with readyToUse false and no matching content means the controller is not running - which is what the _monolithic template's unpinned kubectl install failed at silently"
}
output "crd_check_command" {
  value       = "kubectl get crd volumesnapshots.snapshot.storage.k8s.io volumesnapshotclasses.snapshot.storage.k8s.io volumesnapshotcontents.snapshot.storage.k8s.io"
  description = "The three CRDs the addon installs. Velero's CSI support needs all of them; without them a backup silently skips volume data rather than failing"
}
