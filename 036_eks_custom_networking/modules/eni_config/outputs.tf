output "availability_zones" {
  value       = keys(var.pod_subnets_by_az)
  description = "Zones an ENIConfig was created for. A node in a zone with no ENIConfig cannot give its pods addresses once custom networking is on, so this is worth comparing against the zones the node group actually spans (rules.md B-5)"
}
output "pod_subnets_by_az" {
  value       = var.pod_subnets_by_az
  description = "The zone-to-subnet mapping these ENIConfigs were built from, re-exposed so it can be checked against the cluster without reading the manifests back (rules.md B-5)"
}
output "check_command" {
  value       = "kubectl get eniconfig -o custom-columns=NAME:.metadata.name,SUBNET:.spec.subnet,SGS:.spec.securityGroups"
  description = "Command listing the ENIConfigs as the cluster holds them. ENIConfig is cluster-scoped, so no namespace flag. Compare NAME against 'kubectl get nodes -L topology.kubernetes.io/zone': a node whose zone has no matching ENIConfig gets no pod addresses"
}
output "pod_address_check_command" {
  value       = "kubectl get pods -A -o custom-columns=NS:.metadata.namespace,NAME:.metadata.name,IP:.status.podIP,NODE:.spec.nodeName"
  description = "Command showing which addresses pods actually got. This is the demonstration: pod addresses come from the secondary CIDR while node addresses stay in the primary range. Pods created before custom networking was switched on keep their old addresses until they are recreated"
}
