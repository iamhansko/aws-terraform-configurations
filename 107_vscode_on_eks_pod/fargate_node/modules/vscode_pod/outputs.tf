output "name" {
  value       = var.name
  description = "Name shared by the objects, re-exposed so the caller and the verification commands read one value (rules.md B-5)"
}

output "namespace" {
  value       = var.namespace
  description = "Namespace the objects were created in"
}

output "ingress_name" {
  value       = var.ingress_name
  description = "Name of the Ingress"
}

output "pod_name" {
  # Stable because this is a StatefulSet: replica 0 is always <name>-0, which is what makes the exec
  # and log commands below possible to write down at all.
  value       = "${var.name}-0"
  description = "Name of the first pod, which a StatefulSet makes predictable"
}

output "container_port" {
  value       = var.container_port
  description = "Port code-server listens on, which the caller also needs for the load balancer's rule to the pods (rules.md B-5)"
}

output "rollout_status_command" {
  value       = "kubectl -n ${var.namespace} rollout status statefulset ${var.name} --timeout=10m"
  description = "Waits for the pod to be ready. Pending forever with a 3 CPU request usually means the node group is too small rather than the image being wrong"
}

output "pod_status_command" {
  value       = "kubectl -n ${var.namespace} get pod ${var.name}-0 -o wide"
  description = "Where the pod landed and whether it is running. Init:0/1 means the tools init container is still downloading"
}

output "init_log_command" {
  value       = "kubectl -n ${var.namespace} logs ${var.name}-0 -c tools"
  description = "Output of the tools init container. A failure here holds the pod in Init and names which download broke"
}

output "tools_check_command" {
  value       = "kubectl -n ${var.namespace} exec ${var.name}-0 -- sh -c 'kubectl version --client --output=yaml | head -3; helm version --short; eksctl version; terraform version | head -1; aws --version'"
  description = "Every tool the init container installed, answering from inside the pod. These live in a volume, so they are still there after a restart - which was not true of the original's kubectl exec install"
}

output "cluster_access_check_command" {
  value       = "kubectl -n ${var.namespace} exec ${var.name}-0 -- kubectl get nodes"
  description = "kubectl inside the pod talking to the cluster through the mounted kubeconfig. \"You must be logged in to the server\" here means the pod's role has no access entry rather than a missing kubeconfig"
}

output "ingress_status_command" {
  value       = "kubectl -n ${var.namespace} get ingress ${var.ingress_name}"
  description = "An empty ADDRESS with a class set points at the controller log; an empty CLASS means no controller claimed the Ingress at all"
}

output "load_balancer_hostname_command" {
  value       = "kubectl -n ${var.namespace} get ingress ${var.ingress_name} -o jsonpath='{.status.loadBalancer.ingress[0].hostname}{\"\\n\"}'"
  description = "The address the controller attached. Compare it against the pre-created load balancer's DNS name - the same value means the controller adopted it rather than building a second one (rules.md G-3)"
}
