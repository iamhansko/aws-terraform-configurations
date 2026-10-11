# Every value here is a projection of local.outputs in main.tf. No output in this
# file builds its own expression: the same map feeds the README written onto the
# workbench, and an output declared outside it would be missing from that README
# with nothing to signal the gap (rules.md H-2).
#
# description is the one thing that cannot come from the map. Terraform rejects an
# expression in an output's description ("Variables not allowed"), so the wording
# is literal in both places while the value stays in one.
#
# Nothing here is sensitive. The Jenkins password and the GitLab root password are
# both exposed as commands that read them out of the cluster's Secrets rather than
# as values, because this README is written to disk on a code-server instance that
# serves with authentication disabled (rules.md H-2).

output "vscode_url" {
  value       = local.outputs.vscode_url.value
  description = "URL of the code-server web UI on the workbench instance"
}

output "cluster_name" {
  value       = local.outputs.cluster_name.value
  description = "Name of the EKS cluster, which is also the elbv2.k8s.aws/cluster tag on both pre-created load balancers"
}

output "gitlab_url" {
  value       = local.outputs.gitlab_url.value
  description = "GitLab web URL, which resolves through the wildcard record this project creates in the domain's hosted zone, or through the one added by hand when create_dns_record is false"
}

output "gitlab_initial_root_password_command" {
  value       = local.outputs.gitlab_initial_root_password_command.value
  description = "Command that prints the root password the GitLab chart generated into a Secret"
}

output "gitlab_load_balancer_url" {
  value       = local.outputs.gitlab_load_balancer_url.value
  description = "Address of the network load balancer Terraform pre-created for GitLab"
}

output "gitlab_adoption_check_command" {
  value       = local.outputs.gitlab_adoption_check_command.value
  description = "Command that reads the load balancer address the controller attached to the GitLab Service, for comparison against the pre-created one"
}

output "jenkins_url" {
  value       = local.outputs.jenkins_url.value
  description = "Jenkins web URL, served through the pre-created network load balancer"
}

output "jenkins_admin_username" {
  value       = local.outputs.jenkins_admin_username.value
  description = "Login name for the Jenkins UI"
}

output "jenkins_admin_password_command" {
  value       = local.outputs.jenkins_admin_password_command.value
  description = "Command that reads the Jenkins administrator password back out of the chart's Secret"
}

output "jenkins_ingress_status_command" {
  value       = local.outputs.jenkins_ingress_status_command.value
  description = "Command that shows the Jenkins Ingress and the class it asks for"
}

output "jenkins_adoption_check_command" {
  value       = local.outputs.jenkins_adoption_check_command.value
  description = "Command that reads the load balancer address the controller attached to the Jenkins ingress Service"
}

output "storage_class_check_command" {
  value       = local.outputs.storage_class_check_command.value
  description = "Command that lists the StorageClasses, to confirm gp3 is the only one marked default"
}

output "load_balancer_count_command" {
  value       = local.outputs.load_balancer_count_command.value
  description = "Command that lists every load balancer tagged for this cluster; more than two means adoption failed"
}

output "update_kubeconfig_command" {
  value       = local.outputs.update_kubeconfig_command.value
  description = "Command that points kubectl on the workbench at the cluster"
}
