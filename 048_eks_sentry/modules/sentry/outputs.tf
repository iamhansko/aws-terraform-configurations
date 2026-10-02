output "release_name" {
  value       = helm_release.sentry.name
  description = "Name of the Helm release"
}
output "chart_version" {
  value       = var.chart_version
  description = "Pinned chart version, re-exposed so what is installed is visible without reading the module (rules.md B-5)"
}
output "namespace" {
  value       = var.namespace
  description = "Namespace Sentry runs in, re-exposed so callers do not restate it (rules.md B-5)"
}
output "admin_email" {
  value       = var.admin_email
  description = "Login name for the Sentry admin user. The email is not secret; the password deliberately has no output (rules.md H-2)"
}
output "ingress_class_name" {
  value       = var.ingress_class_name
  description = "IngressClass Sentry's Ingress asks for. Has to match the class the ingress controller owns, or the Ingress is created and never gets an address (rules.md G-1)"
}
# No output carries the admin password. Every output is rendered into a README on an instance
# whose code-server has no authentication in front of it, so a password there would be
# readable by anyone who can reach that instance (rules.md H-2). The _monolithic template put
# both the email and the password into a single plaintext output.
output "admin_password_check_command" {
  value       = "kubectl -n ${var.namespace} get secret ${var.release_name} -o jsonpath='{.data.user-password}' | base64 -d"
  description = "Command reading the admin password back out of the release's Secret, for whoever already has cluster access. A command rather than the value, because this text is also written into an unauthenticated README (rules.md H-2)"
}
output "rollout_command" {
  value       = "kubectl -n ${var.namespace} rollout status deployment ${var.release_name}-web"
  description = "Command confirming the Sentry web deployment finished rolling out. This is the one to watch after the apply returns: the dashboard answers only once it is Available"
}
output "pods_command" {
  value       = "kubectl -n ${var.namespace} get pods -o wide"
  description = "Command listing every pod the chart brings, including the PostgreSQL, Redis, Kafka, ZooKeeper and ClickHouse subcharts. Pods Pending here point at volume provisioning rather than at Sentry"
}
output "ingress_command" {
  value       = "kubectl -n ${var.namespace} get ingress -o wide"
  description = "Command showing Sentry's Ingress and whether the controller gave it an address. An empty ADDRESS means the ingress controller is not reconciling it - usually a class mismatch"
}

output "install_progress_command" {
  # What "context deadline exceeded" does not tell you. Helm reports only that the timeout expired, so
  # the question - which of the twelve hook weights it was still on - has to be asked of the cluster.
  # The hook Jobs are ordered by weight here, so the last one to have completed is where it got to.
  value       = "kubectl -n ${var.namespace} get jobs -o custom-columns='JOB:.metadata.name,COMPLETIONS:.status.succeeded,FAILED:.status.failed,AGE:.metadata.creationTimestamp' && kubectl -n ${var.namespace} get pods --field-selector status.phase!=Running,status.phase!=Succeeded"
  description = "Where a timed-out install got to. The chart installs through 12 serialized helm hook weights - db-check, snuba-db-init, snuba-migrate, db-init, user-create, then five waves of Deployments - and the last completed Job names the wave it was on. Pods listed after it are what it was waiting for"
}

output "migration_log_command" {
  value       = "kubectl -n ${var.namespace} logs job/${var.release_name}-snuba-migrate --tail 50 ; kubectl -n ${var.namespace} logs job/${var.release_name}-db-init --tail 50"
  description = "The two migration Jobs, which are the slowest links in the hook chain and the usual place a timeout is spent. Note both carry hook-delete-policy: hook-succeeded, so a successful Job is deleted and \"not found\" here means it passed"
}

output "pending_reason_command" {
  value       = "kubectl -n ${var.namespace} get events --field-selector type=Warning --sort-by=.lastTimestamp | tail -20"
  description = "Why a pod has not started. \"Too many pods\" is the node group's per-node pod limit rather than its CPU or memory; FailedAttachVolume or a Pending claim is the EBS CSI driver; ImagePullBackOff on a first install is usually just slow"
}

output "main_workloads_command" {
  # The apply no longer blocks on these, so they have to be checked afterwards. sentry-web and
  # sentry-snuba-api are the two whose readiness probes depend on the migrations the post-install hooks
  # run, which is exactly why waiting on them during install deadlocks.
  value       = "kubectl -n ${var.namespace} rollout status deployment ${var.release_name}-web --timeout=15m && kubectl -n ${var.namespace} rollout status deployment ${var.release_name}-snuba-api --timeout=15m"
  description = "Waits for the two Deployments the install deliberately does not wait for. Their readiness probes (/_health/ and /health) need the database schema the hook-driven migrations create, so they only become healthy after the hooks have finished - checking them here rather than during install is what avoids the deadlock"
}
output "bitnami_image_namespace" {
  value       = var.bitnami_image_namespace
  description = "Docker Hub namespace the Bitnami-based subchart images are pulled from, re-exposed so the value actually in effect is visible rather than restated by the caller (rules.md B-5)"
}
output "image_pull_check_command" {
  value       = "kubectl -n ${var.namespace} get events --field-selector type=Warning | grep -iE 'pull|not found'"
  description = "Image pull warnings, including the registry's own wording. The first thing to run when the install fails in a hook: a hook that waits for a dependency reports only its own DeadlineExceeded, so an image that cannot be pulled shows up here and nowhere in Terraform's error. \"not found\" means the tag is gone from the registry rather than unauthorised, which is what moving the Bitnami namespace caused"
}
