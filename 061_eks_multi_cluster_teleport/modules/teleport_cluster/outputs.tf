output "cluster_host" {
  value       = var.cluster_host
  description = "Host name clients reach the cluster on, re-exposed so the DNS records and the web URL read one value (rules.md B-5)"
}
output "web_url" {
  value       = "https://${var.cluster_host}"
  description = "Where the Teleport web UI answers, once the DNS records point at the load balancer and the certificate has been issued"
}
output "namespace" {
  value       = var.namespace
  description = "Namespace Teleport runs in"
}
output "release_name" {
  value       = var.release_name
  description = "Name of the release, which is also the proxy Service name and the auth Deployment's prefix"
}
output "chart_version" {
  value       = var.chart_version
  description = "Chart version installed, which is also the Teleport version - and the version the DynamoDB state format belongs to (rules.md B-5)"
}
output "service_stack_tag" {
  value       = "${var.namespace}/${var.release_name}"
  description = "The <namespace>/<name> value the AWS Load Balancer Controller writes into its service.k8s.aws/stack tag for the proxy Service. A pre-created load balancer must carry exactly this to be adopted rather than duplicated, so it is derived here instead of being restated by the caller (rules.md B-5/G-3)"
}
output "iam_role_arn" {
  value       = aws_iam_role.teleport_iam_role.arn
  description = "IRSA role Teleport's service accounts assume for DynamoDB and S3. The _monolithic template put the same permissions on the node instance role, where every pod on the cluster could use them through IMDS"
}
output "proxy_target_port" {
  value       = var.proxy_target_port
  description = "Port the proxy pod listens on. With target type ip the load balancer reaches this port directly, so it is what the pod-side security group rule opens rather than the Service port (rules.md G-2)"
}
output "proxy_service_command" {
  value       = "kubectl -n ${var.namespace} get service ${var.release_name} -o wide"
  description = "The proxy Service and the address the controller attached to it. Note the Service is named after the release - the _monolithic template's script looked for service/teleport-proxy, which the chart does not create, so every step after it was skipped"
}
output "load_balancer_hostname_command" {
  value       = "kubectl -n ${var.namespace} get service ${var.release_name} -o jsonpath='{.status.loadBalancer.ingress[0].hostname}'"
  description = "Just the load balancer's DNS name. Compare it against the pre-created one: the same value means it was adopted, a different value means a second load balancer was built instead (rules.md G-3)"
}
output "certificate_command" {
  value       = "kubectl -n ${var.namespace} get certificate ${var.release_name} -o wide"
  description = "Whether the certificate was issued. Ready=False here is the usual reason the proxy never becomes ready, and the reason is one level down in the Challenge object"
}
output "status_command" {
  value       = "kubectl -n ${var.namespace} exec deploy/${var.release_name}-auth -- tctl status"
  description = "Teleport's own view of itself: cluster name, version, and the CA fingerprints. Reaching this at all proves the DynamoDB backend is readable"
}
# The three user commands below are the in-cluster half only. They name no cluster, because
# they are run by the operator from the terminal that ran terraform apply, and the root puts
# the update-kubeconfig that points that terminal's kubectl at this cluster in front of each.
#
# No -it on any of them. None reads from stdin, and on the operator's side Git Bash on Windows
# hands kubectl a pipe rather than a console, so -t only adds "Unable to use a TTY" in front of
# the invite link.
output "add_user_command" {
  value       = "kubectl -n ${var.namespace} exec deploy/${var.release_name}-auth -- tctl users add ${var.user_name} --roles=access,editor --logins=root --kubernetes-groups=${local.kubernetes_group}"
  description = "Creates the first user and prints a single-use invite link. Deliberately a command rather than something the apply runs: the link is valid for an hour and can only be used once, so producing it during an apply means it has usually expired by the time anyone reads the output - and putting it in a Terraform output would write the credential to state (rules.md H-2). --kubernetes-groups is what the preset access role turns into Kubernetes access; without it Teleport refuses every kubectl request from this user"
}
output "reset_user_command" {
  value       = "kubectl -n ${var.namespace} exec deploy/${var.release_name}-auth -- tctl users reset ${var.user_name}"
  description = "Issues a new invite link for the same account, for when add_user_command answers that it already exists: its first link expired unused, or the account was left in the DynamoDB backend by an earlier deployment. Discards the account's password and second factor devices and keeps its roles and traits. The new link is valid for eight hours"
}
output "grant_kubernetes_access_command" {
  value       = "kubectl -n ${var.namespace} exec deploy/${var.release_name}-auth -- tctl users update ${var.user_name} --set-kubernetes-groups=${local.kubernetes_group}"
  description = "Gives an existing user the Kubernetes group, for one created without --kubernetes-groups. Replaces the user's kubernetes_groups trait rather than appending to it. Takes effect at the user's next tsh login: traits are copied into the certificate when it is issued, so a session from before this keeps being refused"
}
output "kubernetes_group" {
  value       = local.kubernetes_group
  description = "Kubernetes group Teleport impersonates for its users, and the subject of the ClusterRoleBinding that gives it kubernetes_cluster_role (rules.md B-5)"
}
output "kubernetes_cluster_role" {
  value       = var.kubernetes_cluster_role
  description = "ClusterRole that group is bound to - what a user reaching the cluster through Teleport can do"
}
output "kube_login_command" {
  value       = "tsh login --proxy=${var.cluster_host}:${var.load_balancer_port} --user=${var.user_name} && tsh kube ls && tsh kube login ${var.kube_cluster_name}"
  description = "The point of the project, from a client's side: authenticate to Teleport as the account the add-user command created, list the Kubernetes clusters it knows about, and get a kubeconfig for one - without an IAM principal or an EKS access entry for the person doing it. --user is not optional in practice: tsh defaults to the local login, which on the VS Code instance is ec2-user, an account Teleport does not have"
}
