output "efs_claim_names" {
  # The keys, which are also the claim names - the module deliberately uses one name for the PV and
  # its claim so a caller mounting the claim does not have to know both (rules.md B-5).
  value       = keys(var.efs_volumes)
  description = "Names of the EFS claims, which are also the names of their PersistentVolumes"
}

output "s3_claim_names" {
  value       = keys(var.s3_volumes)
  description = "Names of the Mountpoint for S3 claims, which are also the names of their PersistentVolumes"
}

output "claim_names" {
  value       = concat(keys(var.efs_volumes), keys(var.s3_volumes))
  description = "Every claim this module created, for a caller that mounts all of them"
}

output "binding_check_command" {
  value       = "kubectl -n ${var.namespace} get pvc,pv"
  description = "Bound is the only state worth seeing. A claim stuck in Pending against a statically provisioned volume is usually a mismatch in accessModes or capacity; a claim that bound to a volume nobody declared means storageClassName was left unset and the cluster's default class provisioned one"
}

output "mount_check_command" {
  value       = "kubectl -n ${var.namespace} get pv -o custom-columns='NAME:.metadata.name,DRIVER:.spec.csi.driver,HANDLE:.spec.csi.volumeHandle,BUCKET:.spec.csi.volumeAttributes.bucketName'"
  description = "Which driver each volume uses and what it points at. This is where an EFS handle missing its access point, or a bucket name from the wrong region, becomes visible"
}
