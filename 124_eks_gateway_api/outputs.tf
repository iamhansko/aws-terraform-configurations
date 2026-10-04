# Every value here is a projection of local.outputs in main.tf, which the README written onto the workbench
# renders from the same map - so no value expression exists twice, and an output cannot be added without also
# appearing in that README (rules.md B-5/H-2).
#
# description is the one thing that cannot be projected: Terraform rejects an expression in an output's
# description ("Variables not allowed"), so the wording is a literal on both sides.
output "vscode_url" {
  value       = local.outputs.vscode_url.value
  description = "Open the IDE here. The cluster's API server is private, so this instance is the only place kubectl works"
}
output "what_this_shows" {
  value       = local.outputs.what_this_shows.value
  description = "The chain from GatewayClass to pods, and which object becomes which piece of AWS"
}
output "gateway_address_command" {
  value       = local.outputs.gateway_address_command.value
  description = "1. The ALB's DNS name, read off the Gateway's status - the controller created it, so Terraform does not know it"
}
output "curl_command" {
  value       = local.outputs.curl_command.value
  description = "2. Whether the Gateway answers, and which pod handled the request"
}
output "gateway_status_command" {
  value       = local.outputs.gateway_status_command.value
  description = "3. The Gateway and HTTPRoute status the controller writes back"
}
output "controller_log_command" {
  value       = local.outputs.controller_log_command.value
  description = "4. The controller log, which is the only place that says whether its Gateway controllers started"
}
output "load_balancer_check_command" {
  value       = local.outputs.load_balancer_check_command.value
  description = "5. Load balancers tagged for this cluster. One is correct"
}
output "target_health_command" {
  value       = local.outputs.target_health_command.value
  description = "6. Whether the target group's members are healthy, and whether the pods answer on the container port. The first thing to run on a 502"
}
output "crd_check_command" {
  value       = local.outputs.crd_check_command.value
  description = "7. Which Gateway API CRDs are installed, standard-channel and AWS-vended"
}
output "gateway_api_version" {
  value       = local.outputs.gateway_api_version.value
  description = "The pinned Gateway API and controller releases, which have to agree with each other"
}
output "cluster_name" {
  value       = local.outputs.cluster_name.value
  description = "Name of the EKS cluster"
}
output "cluster_endpoint" {
  value       = local.outputs.cluster_endpoint.value
  description = "The cluster's API server endpoint. Private only, which is why the bootstrap runs through SSM"
}
output "service_ipv4_cidr" {
  value       = local.outputs.service_ipv4_cidr.value
  description = "The Service CIDR the cluster actually got, read back from the resource"
}
output "update_kubeconfig_command" {
  value       = local.outputs.update_kubeconfig_command.value
  description = "Re-points kubectl at the cluster. Only works from inside the VPC"
}
output "private_key_command" {
  value       = local.outputs.private_key_command.value
  description = "Reads the workbench's SSH private key out of SSM Parameter Store"
}
output "ssm_failure_diagnosis" {
  value       = local.outputs.ssm_failure_diagnosis.value
  description = "How to get the real error out of an SSM association that did not reach Success"
}
output "teardown" {
  value       = local.outputs.teardown.value
  description = "Delete the Gateway before terraform destroy, or the controller's load balancer outlives the cluster"
}
