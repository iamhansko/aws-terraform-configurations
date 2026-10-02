output "namespace" {
  value       = var.namespace
  description = "Namespace the demo application runs in, re-exposed so the root's commands read one value (rules.md B-5)"
}
output "name" {
  value       = var.name
  description = "Name of the demo Deployment, Service and VirtualService"
}
output "routing_applied" {
  value       = var.route_traffic
  description = "Whether the Gateway and VirtualService were created. False means the gateway proxy has no listener on the traffic port, so the load balancer URL refuses connections while every resource still reports healthy (rules.md B-5)"
}
output "sidecar_check_command" {
  value       = "kubectl -n ${var.namespace} get pods -o jsonpath='{range .items[*]}{.metadata.name}{\"\\t\"}{range .spec.containers[*]}{.name}{\" \"}{end}{\"\\n\"}{end}'"
  description = "Lists each pod's containers. Two names - the application and istio-proxy - means injection worked. One name means the pod is not in the mesh, which is not an error anywhere: it runs and serves traffic, and simply never appears in Kiali"
}
output "rollout_status_command" {
  value       = "kubectl -n ${var.namespace} rollout status deployment ${var.name} --timeout=5m"
  description = "Waits for the application pods. Worth running before reading anything into the mesh, since a pod still pulling its image looks the same as one being refused a sidecar"
}
output "routing_check_command" {
  value       = "kubectl -n ${var.namespace} get gateway,virtualservice"
  description = "The two objects that decide whether the load balancer URL serves anything. Empty output means route_traffic was false, and the URL will refuse connections"
}
output "traffic_generator_command" {
  value       = "kubectl -n ${var.namespace} run curl --rm -it --restart=Never --image=public.ecr.aws/docker/library/curlimages/curl:latest -- sh -c 'for i in $(seq 1 200); do curl -s -o /dev/null http://${var.name}.${var.namespace}.svc.cluster.local:${var.service_port}/; done'"
  description = "Sends traffic from inside the mesh so Kiali's graph has edges to draw. Kiali builds the graph from metrics rather than from configuration, so a mesh nobody is using looks identical to one that is not working"
}
