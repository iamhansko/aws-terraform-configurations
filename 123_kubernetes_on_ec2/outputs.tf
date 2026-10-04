# Every value here is a projection of local.outputs in main.tf. No output in this file
# builds its own expression: the same map feeds the README written onto the workbench,
# and an output declared outside it would be missing from that README with nothing to
# signal the gap (rules.md H-2).
#
# description is the one thing that cannot come from the map. Terraform rejects an
# expression in an output's description ("Variables not allowed"), so the wording is
# literal in both places while the value stays in one.

output "vscode_url" {
  value       = local.outputs.vscode_url.value
  description = "URL of the code-server web UI on the workbench, which is the only place kubectl reaches this cluster"
}

output "ingress_url" {
  value       = local.outputs.ingress_url.value
  description = "URL of the demo workload, reachable from the workbench because its /etc/hosts maps the host to the ingress Elastic IP"
}

output "ingress_public_ip" {
  value       = local.outputs.ingress_public_ip.value
  description = "Elastic IP attached to the worker node, where Traefik binds its host ports"
}

output "control_plane_private_ip" {
  value       = local.outputs.control_plane_private_ip.value
  description = "Private address kubeadm advertised as the API server endpoint"
}

output "worker_node_name" {
  value       = local.outputs.worker_node_name.value
  description = "Kubernetes node name of the worker, which is the value the Traefik nodeSelector matches"
}

output "cluster_state_bucket" {
  value       = local.outputs.cluster_state_bucket.value
  description = "Name of the bucket the three machines exchange the kubeconfig and the kubeadm join command through"
}

output "node_status_command" {
  value       = local.outputs.node_status_command.value
  description = "Command that shows whether both nodes joined and became Ready"
}

output "cluster_state_objects_command" {
  value       = local.outputs.cluster_state_objects_command.value
  description = "Command that lists the handoff objects, for telling a failed kubeadm init apart from a failed join"
}

output "calico_status_command" {
  value       = local.outputs.calico_status_command.value
  description = "Command that shows the Calico node DaemonSet"
}

output "traefik_status_command" {
  value       = local.outputs.traefik_status_command.value
  description = "Command that shows the Traefik pod and the node it landed on"
}

output "workload_status_command" {
  value       = local.outputs.workload_status_command.value
  description = "Command that shows the demo Deployment, Service and Ingress"
}

output "curl_root_command" {
  value       = local.outputs.curl_root_command.value
  description = "Command that requests the demo workload's first Ingress path from the workbench"
}

output "curl_second_path_command" {
  value       = local.outputs.curl_second_path_command.value
  description = "Command that requests the demo workload's last Ingress path from the workbench"
}

output "kubeconfig_refresh_command" {
  value       = local.outputs.kubeconfig_refresh_command.value
  description = "Command that re-downloads the admin kubeconfig from the handoff bucket onto the workbench"
}
