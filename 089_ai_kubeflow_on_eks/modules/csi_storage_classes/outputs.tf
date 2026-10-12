output "storage_class_name" {
  value       = var.storage_class_name
  description = "Name of the StorageClass this module creates. Re-exposed for the README rather than for another module to consume: nothing references it, because Kubeflow's claims reach the class through its default annotation (rules.md B-5)"
}
output "storage_class_check_command" {
  value       = "kubectl get storageclass"
  description = "Lists the cluster's StorageClasses and which one is default. Exactly one line should read (default) and it should be the gp3 one with provisioner ebs.csi.aws.com. The gp2 line is EKS's own, and its kubernetes.io/aws-ebs provisioner has provisioned nothing since Kubernetes 1.23"
}
output "pending_claims_command" {
  value       = "kubectl -n ${var.workload_namespace} get pvc"
  description = "Shows Kubeflow's claims and whether they bound. Worth running even when the install reported success: the dashboard has no volume, so it comes up regardless, and a claim Pending with an empty STORAGECLASS column is Katib and the pipeline store silently dead"
}
