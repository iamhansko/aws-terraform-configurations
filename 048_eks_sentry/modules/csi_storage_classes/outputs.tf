output "storage_class_name" {
  value       = var.storage_class_name
  description = "Name of the StorageClass this module creates. Re-exposed for the README rather than for another module to consume: nothing references it, because the chart's claims reach the class through its default annotation (rules.md B-5)"
}
output "storage_class_check_command" {
  value       = "kubectl get storageclass"
  description = "Lists the cluster's StorageClasses and which one is default. Exactly one line should be marked (default) and it should be the gp3 one with provisioner ebs.csi.aws.com. No (default) anywhere means the chart's eight claims have nothing to resolve to, which is what a release timing out in its hook chain usually turns out to be"
}
