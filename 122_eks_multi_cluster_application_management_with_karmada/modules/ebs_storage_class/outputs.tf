output "name" {
  value       = var.name
  description = "Name of the StorageClass, re-exposed so the control plane module names the class that was actually created rather than restating the string (rules.md B-5). A claim naming a class that does not exist stays Pending with no volume and no error on the StatefulSet that owns it"
}
output "check_command" {
  value       = "kubectl get storageclass ${var.name}"
  description = "Whether the class exists and which provisioner it names. Worth reading when Karmada's etcd pod is Pending: no class means this module did not apply, and a class whose provisioner is not ebs.csi.aws.com means the EBS CSI driver addon is missing"
}
