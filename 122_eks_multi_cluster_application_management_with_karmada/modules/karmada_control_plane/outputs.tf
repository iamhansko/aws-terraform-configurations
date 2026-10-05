output "release_name" {
  value       = helm_release.karmada.name
  description = "Name of the Helm release, which is also the prefix on every object the chart created"
}
output "namespace" {
  value       = helm_release.karmada.namespace
  description = "Namespace the control plane runs in"
}
output "chart_version" {
  value       = helm_release.karmada.version
  description = "Chart version actually installed. Worth having as an output because the Karmada repository serves its index from a moving branch, so this is the record of what a given apply resolved to"
}
output "karmada_image_version" {
  value       = var.karmada_image_version
  description = "Tag the Karmada component images were pinned to, re-exposed from the input because it is not visible in the release otherwise - the chart's own karmadaImageVersion value does not reach the component tags (rules.md B-5, and see main.tf for the YAML anchor that causes it)"
}
output "node_port" {
  value       = var.node_port
  description = "The nodePort the API server Service was published on, re-exposed so a mismatch with the load balancer's listener is visible in terraform output rather than only as unhealthy targets (rules.md B-5)"
}
output "pods_check_command" {
  value       = "kubectl -n ${var.namespace} get pods"
  description = "The control plane's pods on the host cluster. Expect etcd, karmada-apiserver, karmada-aggregated-apiserver, karmada-kube-controller-manager, karmada-controller-manager, karmada-scheduler and karmada-webhook - seven, not counting replicas. A pod stuck in its wait-for-etcd init container means etcd never got a volume, not that the component is broken"
}
output "etcd_claim_check_command" {
  value       = "kubectl -n ${var.namespace} get pvc -l app=etcd"
  description = "Whether etcd's volume claim bound. Pending here is the single most likely reason a Karmada install appears to hang, because every other component waits on etcd - and the cause is upstream of this module, in the EBS CSI driver addon or the StorageClass"
}
output "kubeconfig_secret_command" {
  value       = "kubectl -n ${var.namespace} get secret ${var.release_name}-kubeconfig -o jsonpath='{.data.kubeconfig}' | base64 -d"
  description = "The kubeconfig the chart generated for the Karmada API server, pointing at its in-cluster Service name. Useful from inside the host cluster; from outside, use the kubeconfig this project writes onto the workbench instead, which names the load balancer"
}
