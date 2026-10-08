# Every value here is a projection of local.outputs in main.tf, which the README written onto the
# workbench renders from the same map - so no value expression exists twice (rules.md B-5/H-2).
#
# The descriptions are the one thing that cannot be projected: Terraform does not allow an expression
# in an output description ("Variables not allowed"), so the wording is repeated here as a literal
# while the values are not.

output "vscode_ec2_url" {
  value       = local.outputs.vscode_ec2_url.value
  description = "The instance, not the pod. Open the IDE here and run every command below from its terminal"
}

output "vscode_pod_url" {
  value       = local.outputs.vscode_pod_url.value
  description = "The point of this project: the same IDE, running as a pod, reached through the ALB. The address is known from state because Terraform pre-created the load balancer rather than letting the controller build one (rules.md G-3)"
}

output "security_warning" {
  value       = local.outputs.security_warning.value
  description = "code-server in the pod runs with auth disabled, the pod's role holds AdministratorAccess and a cluster-admin access entry, and the load balancer accepts 0.0.0.0/0 by default. Anything that reaches the URL above has a root shell in this account - narrow alb_allow_inbound_from_anywhere and vscode_pod_iam_policy_arns before leaving it up"
}

output "cluster_name" {
  value       = local.outputs.cluster_name.value
  description = "Name of the EKS cluster, which is also the elbv2.k8s.aws/cluster tag on the pre-created load balancer"
}

output "pod_rollout_command" {
  value       = local.outputs.pod_rollout_command.value
  description = "Init:0/1 means the tools init container is still downloading. Pending that never clears is the 3 CPU request against a node group that is too small, not a bad image"
}

output "pod_tools_command" {
  value       = local.outputs.pod_tools_command.value
  description = "kubectl, helm, eksctl, terraform and the AWS CLI, installed by an init container into a volume. The original installed these with kubectl exec, so they were gone after every restart"
}

output "pod_cluster_access_command" {
  value       = local.outputs.pod_cluster_access_command.value
  description = "Uses the kubeconfig mounted from a ConfigMap and the credentials from the pod's identity binding. \"You must be logged in to the server\" means the access entry is missing rather than the kubeconfig"
}

output "pod_identity_command" {
  value       = local.outputs.pod_identity_command.value
  description = "IRSA on this variant, so the binding is an annotation on the service account. Pod Identity is not available: its agent is a DaemonSet and this cluster has no node to run one on"
}

output "fargate_placement_command" {
  value       = local.outputs.fargate_placement_command.value
  description = "Every node name starts with fargate-ip-, and there is one per pod - a Fargate pod is its own micro VM. CoreDNS appearing here at all is what compute_type Fargate bought: with the annotation EKS ships, its pods never schedule on a cluster like this"
}

output "volume_binding_command" {
  value       = local.outputs.volume_binding_command.value
  description = "Statically provisioned, because the driver built into the Fargate runtime does not do the dynamic access-point workflow. A claim stuck in Pending is an accessModes or capacity mismatch rather than a missing driver"
}

output "volume_write_command" {
  value       = local.outputs.volume_write_command.value
  description = "The difference between this variant and the base one, which created the same file system and mounted nothing. A mount that hangs rather than fails is the EFS security group: NFS reaches it only from the cluster security group"
}

output "ingress_status_command" {
  value       = local.outputs.ingress_status_command.value
  description = "An empty ADDRESS with a class set points at the controller log; an empty CLASS means no controller claimed it at all - which is exactly what the original produced, because its helm install never ran"
}

output "adoption_check_command" {
  value       = local.outputs.adoption_check_command.value
  description = "One load balancer is correct. Two means the controller did not adopt the pre-created one and built its own, which is a tag mismatch rather than an error (rules.md G-3)"
}

output "adopted_hostname_command" {
  value       = local.outputs.adopted_hostname_command.value
  description = "The hostname the controller attached to the Ingress should be the same load balancer as the URL above"
}

output "target_health_command" {
  value       = local.outputs.target_health_command.value
  description = "Pod IPs registered by the controller. All unhealthy with a healthy pod means the rule from the load balancer to the pod's port is missing - and on this variant that rule is load_balancer_to_pods in the configuration rather than something the controller writes, so it is a plan to read rather than a controller log (rules.md G-2)"
}

output "load_balancer_security_groups_command" {
  value       = local.outputs.load_balancer_security_groups_command.value
  description = "One group, the frontend group this configuration declares. A second group named k8s-traffic-<cluster>-<hash> is the controller's shared backend group, which it creates and attaches whenever enable_backend_security_group is on and an Ingress asks it to manage the pod-side rules - both of which this variant turns off, so anything beyond the one group here means one of them came back (rules.md G-2)"
}

output "controller_log_command" {
  value       = local.outputs.controller_log_command.value
  description = "Where a rejected annotation combination explains itself. A backendSG message here means manage-backend-security-group-rules is being set somewhere while enable_backend_security_group is false, which is the pairing rules.md G-2 describes"
}

output "update_kubeconfig_command" {
  value       = local.outputs.update_kubeconfig_command.value
  description = "User data already ran this, so kubectl works out of the box. Re-run it if the kubeconfig is ever lost"
}
