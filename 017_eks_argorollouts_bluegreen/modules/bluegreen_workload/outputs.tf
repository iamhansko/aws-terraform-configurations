output "namespace" {
  value       = var.namespace
  description = "Namespace the Rollout runs in (rules.md B-5)"
}
output "rollout_name" {
  value       = var.rollout_name
  description = "Name of the Rollout object"
}
output "watch_command" {
  value       = "kubectl argo rollouts get rollout ${var.rollout_name} -n ${var.namespace} --watch"
  description = "Command following the rollout's state. This is where a blue/green promotion is visible from the cluster side (rules.md H-2)"
}
output "promote_command" {
  value       = "kubectl argo rollouts promote ${var.rollout_name} -n ${var.namespace}"
  description = "Command promoting the preview version to active. Needed because auto_promotion_enabled is false, which is what makes the pause observable"
}
output "new_version_command" {
  value       = "kubectl argo rollouts set image ${var.rollout_name} -n ${var.namespace} ${var.app_label}=public.ecr.aws/docker/library/nginx:1.29"
  description = "Command starting a rollout by changing the image. The Rollout brings up the new version behind the preview Service and waits, rather than replacing the running pods"
}
output "preview_check_command" {
  value       = "kubectl -n ${var.namespace} run curl-preview --rm -i --restart=Never --image=public.ecr.aws/docker/library/curlimages/curl:latest -- curl -s -o /dev/null -w '%%{http_code}\\n' http://${var.preview_service_name}"
  description = "Command reaching the new version through the preview Service while the old one still serves the load balancer. The point of blue/green: the new version is verifiable before it takes traffic"
}
