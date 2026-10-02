# Every output is a projection of local.outputs in main.tf, which is also what the README
# written onto the VS Code instance is rendered from (rules.md H-2). No value expression is
# written here: an output that built its own value would be missing from that README, and
# nothing would fail to say so - the apply would succeed either way. Whether the pattern still
# holds is checked by counting: the number of output blocks here must equal the number of
# entries in local.outputs.
#
# The Sentry admin password is deliberately absent. The _monolithic template published it in a
# plaintext output, which also put it into the instance README that an unauthenticated
# code-server serves; it is reachable only through sentry_admin_password_command
# (rules.md H-2).
#
# description is the one thing repeated, because Terraform rejects an expression there
# ("Variables not allowed") - it has to be a literal.

output "vscode_url" {
  value       = local.outputs.vscode_url.value
  description = "Open the IDE here. The kubectl commands below are meant to be run from its terminal"
}

output "cluster_name" {
  value       = local.outputs.cluster_name.value
  description = "Name of the EKS cluster. The AWS Load Balancer Controller also writes this into the elbv2.k8s.aws/cluster tag it uses to find load balancers it owns"
}

output "cluster_endpoint" {
  value       = local.outputs.cluster_endpoint.value
  description = "API server endpoint. Public so the helm provider could reach it during apply - narrow public_access_cidrs to your own address"
}

output "sentry_url" {
  value       = local.outputs.sentry_url.value
  description = "Served through the pre-created NLB the ingress controller adopts, so the address is known from state at apply time rather than only after reconciliation (rules.md G-3). Sentry takes several minutes after the apply returns before it answers"
}

output "sentry_admin_login" {
  value       = local.outputs.sentry_admin_login.value
  description = "The login name only. The password is deliberately not here: this text is written into a README served by a code-server with no authentication in front of it, and the dashboard above is internet-facing (rules.md H-2). Read the password with the command below"
}

output "sentry_admin_password_command" {
  value       = local.outputs.sentry_admin_password_command.value
  description = "Out of the release's own Secret, for whoever already has cluster access. A command rather than the value, for the reason above"
}

output "sentry_rollout_command" {
  value       = local.outputs.sentry_rollout_command.value
  description = "This is the thing to watch rather than reloading the URL. The chart brings PostgreSQL, Redis, Kafka, ZooKeeper and ClickHouse, so the first install routinely takes tens of minutes"
}

output "sentry_main_workloads_command" {
  value       = local.outputs.sentry_main_workloads_command.value
  description = "The apply deliberately does not wait for these two. Their readiness probes need the database schema that the chart's post-install hooks create, so requiring them during install would deadlock - they come up shortly after the hooks finish, and this is where to confirm it"
}

output "sentry_pods_command" {
  value       = local.outputs.sentry_pods_command.value
  description = "Every pod the chart brings. Pods stuck Pending here are almost always waiting on a volume rather than on Sentry - check the claims with the command below"
}

output "sentry_install_progress_command" {
  value       = local.outputs.sentry_install_progress_command.value
  description = "That is the helm timeout, and it reports nothing else. The chart installs through 12 serialized hook weights - db-check, snuba-db-init, snuba-migrate, db-init, user-create, then five waves of Deployments - so the last completed Job names the wave it was still on, and the pods after it are what it was waiting for"
}

output "sentry_migration_log_command" {
  value       = local.outputs.sentry_migration_log_command.value
  description = "snuba-migrate runs the ClickHouse migrations and is the slowest link in the chain, so it is where a timeout is usually spent. Both Jobs carry hook-delete-policy hook-succeeded, so \"not found\" means the Job passed and was cleaned up"
}

output "sentry_pending_reason_command" {
  value       = local.outputs.sentry_pending_reason_command.value
  description = "\"Too many pods\" is the node group's per-node pod limit rather than its CPU or memory - see node_group_instance_types. A Pending claim or FailedAttachVolume is the EBS CSI driver"
}

output "volume_check_command" {
  value       = local.outputs.volume_check_command.value
  description = "Claims and then the EBS CSI controller's log. Claims Pending means the driver could not provision - usually its IAM role missing AmazonEBSCSIDriverPolicy, which shows up nowhere else"
}

output "sentry_ingress_command" {
  value       = local.outputs.sentry_ingress_command.value
  description = "An empty ADDRESS means the ingress controller is not reconciling Sentry's Ingress, which is normally a class mismatch rather than anything wrong with Sentry"
}

output "adopted_load_balancer_check_command" {
  value       = local.outputs.adopted_load_balancer_check_command.value
  description = "Lists every load balancer tagged for this cluster. One is correct. Two means the controller did not adopt the pre-created one and built its own, which is a tag mismatch rather than an error (rules.md G-3)"
}

output "ingress_hostname_command" {
  value       = local.outputs.ingress_hostname_command.value
  description = "Compare this against the dashboard URL above. They should be the same load balancer"
}

output "sentry_cli_login_command" {
  value       = local.outputs.sentry_cli_login_command.value
  description = "The CLI is already installed on the instance. This points it at this deployment and prompts for a token from the dashboard"
}

output "update_kubeconfig_command" {
  value       = local.outputs.update_kubeconfig_command.value
  description = "User data already ran this, so kubectl works out of the box. Re-run it if the kubeconfig is ever lost"
}
output "storage_class_name" {
  value       = local.outputs.storage_class_name.value
  description = "Name of the default gp3 StorageClass all of Sentry's volume claims resolve through"
}
output "storage_class_check_command" {
  value       = local.outputs.storage_class_check_command.value
  description = "Command that lists the cluster's StorageClasses and which one is default"
}
output "sentry_image_namespace" {
  value       = local.outputs.sentry_image_namespace.value
  description = "Docker Hub namespace the Bitnami-based subchart images are pulled from"
}
output "sentry_image_pull_check_command" {
  value       = local.outputs.sentry_image_pull_check_command.value
  description = "Command that shows image pull warnings in the Sentry namespace"
}
