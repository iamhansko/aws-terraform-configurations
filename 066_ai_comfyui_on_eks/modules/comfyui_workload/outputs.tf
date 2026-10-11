output "namespace" {
  value       = var.namespace
  description = "Namespace ComfyUI runs in, re-exposed so diagnostic commands read one value (rules.md B-5)"
}
output "deployment_name" {
  value       = var.name
  description = "Name of the ComfyUI Deployment"
}
output "pod_role_arn" {
  value       = aws_iam_role.pod.arn
  description = "Role the ComfyUI pod assumes through Pod Identity"
}
output "persistent_volume_claims" {
  value       = { for key, claim in kubectl_manifest.persistent_volume_claim : key => claim.name }
  description = "The Mountpoint claims by purpose (inputs, outputs)"
}
output "pods_command" {
  value       = "kubectl -n ${var.namespace} get pods -l app=${var.name} -o wide"
  description = "Where the ComfyUI pod is and what state it is in. Pending usually means no GPU capacity yet; ImagePullBackOff means the image is missing from ECR"
}
output "logs_command" {
  value       = "kubectl -n ${var.namespace} logs deploy/${var.name} -c comfyui --tail 100"
  description = "ComfyUI's own log, which is where a missing model or a failed S3 upload from the auto model downloader shows up"
}
output "describe_ingress_command" {
  value       = "kubectl -n ${var.namespace} describe ingress ${var.ingress_name}"
  description = "The Ingress and the load balancer controller's events on it. An empty ADDRESS with no events means the controller is not reconciling it at all"
}
output "load_balancer_hostname_command" {
  value       = "kubectl -n ${var.namespace} get ingress ${var.ingress_name} -o jsonpath='{.status.loadBalancer.ingress[0].hostname}'"
  description = "The address the controller attached the Ingress to. Compare it with the pre-created ALB's DNS name - a different name means the ALB was not adopted and a second one was built (rules.md G-3)"
}
output "port_forward_command" {
  value       = "kubectl -n ${var.namespace} port-forward service/${var.service_name} ${var.container_port}:${var.container_port}"
  description = "Reaches ComfyUI from the workbench without CloudFront or the ALB, which tells a problem in the pod apart from one in front of it"
}
output "volumes_command" {
  value       = "kubectl -n ${var.namespace} get pvc && kubectl get pv ${join(" ", [for key in keys(local.volumes) : "${var.name}-${key}-pv"])}"
  description = "The Mountpoint claims and volumes. Both should be Bound"
}
