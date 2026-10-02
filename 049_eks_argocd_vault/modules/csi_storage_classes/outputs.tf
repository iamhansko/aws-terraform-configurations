output "storage_class_name" {
  value       = var.storage_class_name
  description = "Name of the StorageClass this module creates, re-exposed so the Vault module can name it in its claim instead of the root restating the string (rules.md B-5). Passing it as a value is also what orders the release after the class exists"
}
output "storage_class_check_command" {
  value       = "kubectl get storageclass"
  description = "Lists the cluster's StorageClasses and which one is default. The first thing to run when a pod is Pending with 'unbound immediate PersistentVolumeClaims': a gp3 line with provisioner ebs.csi.aws.com means this module applied, and its absence means the claim had nothing to resolve to"
}
output "pending_claims_command" {
  value       = "kubectl get pvc -A"
  description = "Shows every claim and whether it bound. A claim stuck Pending with an empty STORAGECLASS column is the failure this module fixes - the claim named no class and no class was default, so nothing provisioned it"
}
