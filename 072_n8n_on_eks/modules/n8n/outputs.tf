output "namespace" {
  value       = var.namespace
  description = "Namespace everything here lives in, re-exposed so the caller's diagnostic commands read one value (rules.md B-5)"
}
output "name" {
  value       = var.name
  description = "Name of the n8n Deployment and Service"
}
output "service_name" {
  value       = var.name
  description = "Name of the Service the Ingress names as its backend"
}
output "ingress_name" {
  value       = local.ingress_name
  description = "Name of the Ingress. This is the half of the <namespace>/<name> stack tag a pre-created load balancer has to carry to be adopted rather than duplicated (rules.md G-3)"
}
output "ingress_stack_tag" {
  value       = "${var.namespace}/${local.ingress_name}"
  description = "The value the controller writes into its ingress.k8s.aws/stack tag for this Ingress. Derived here rather than restated by the caller, so the tag on a pre-created load balancer cannot drift from the Ingress being reconciled (rules.md B-5/G-3)"
}
output "container_port" {
  value       = var.container_port
  description = "Port n8n listens on. With target-type ip this - not the listener port - is what the pod-side security group rule has to open, so the caller reads it from here rather than restating 5678 (rules.md B-5/G-2)"
}
output "service_port" {
  value       = var.service_port
  description = "Port the Service publishes, which the Ingress names as its backend port. Not the listener port - that is set by the listen-ports annotation and opened on the frontend security group separately (rules.md B-5/G-1)"
}
output "external_url" {
  value       = var.external_url
  description = "The address written into N8N_HOST and WEBHOOK_URL, re-exposed so a mismatch with the load balancer the caller actually built is visible in terraform output rather than only as a webhook nobody can call (rules.md B-5)"
}
output "image" {
  value       = var.image
  description = "The n8n image actually deployed, re-exposed because the _monolithic template's version lived in a kubectl set image call and could not be read off anything"
}
output "rollout_status_command" {
  value       = "kubectl -n ${var.namespace} rollout status deployment ${var.name} --timeout=15m"
  description = "Waits for n8n. Long timeout on purpose: two EBS volumes are provisioned only once their pods are scheduled, Postgres initialises its data directory and runs the role script on first start, and n8n exits and restarts until the database answers"
}
output "postgres_rollout_status_command" {
  value       = "kubectl -n ${var.namespace} rollout status deployment postgres --timeout=15m"
  description = "Waits for Postgres. Worth running first: while it is still initialising, n8n's restarts look like a broken image rather than a database that is not up yet"
}
output "pods_command" {
  value       = "kubectl -n ${var.namespace} get pods,pvc -o wide"
  description = "Both pods and both claims. A pod stuck Pending with a Pending claim is the storage class or the EBS CSI driver rather than anything in the application"
}
output "logs_command" {
  value       = "kubectl -n ${var.namespace} logs deploy/${var.name} --tail 100"
  description = "n8n's own log. A database authentication failure here means the init script did not create the app role - which happens once, on the first start, and leaves no trace anywhere else"
}
output "postgres_init_log_command" {
  value       = "kubectl -n ${var.namespace} logs deploy/postgres --tail 200 | grep -i -A5 init-n8n-user"
  description = "What the role-creation script did during Postgres's first start. It runs only when the data directory is empty, so a cluster rebuilt on an existing volume never runs it again"
}
output "credentials_command" {
  value       = "kubectl -n ${var.namespace} get secret postgres-secret -o go-template='{{range $k, $v := .data}}{{$k}}={{$v | base64decode}}{{\"\\n\"}}{{end}}'"
  description = "Reads the generated Postgres credentials out of the cluster. They are deliberately not exposed as a Terraform output and not written into this instance's README: code-server here has no authentication in front of it, so a password on that disk is a password published (rules.md H-2)"
}
output "ingress_address_command" {
  value       = "kubectl -n ${var.namespace} get ingress ${local.ingress_name}"
  description = "The address the controller assigned. An empty ADDRESS is the failure worth recognising: it means no controller is reconciling this Ingress, which is almost always a missing or misspelled ingressClassName rather than anything about the load balancer (rules.md G-1)"
}
output "ingress_events_command" {
  value       = "kubectl -n ${var.namespace} describe ingress ${local.ingress_name}"
  description = "Where the controller reports what it did or could not do. \"couldn't auto-discover subnets\" here means the subnet role tags and the scheme annotation disagree; no events at all means the Ingress is not being reconciled (rules.md G-1)"
}
# No output for the init Job's name. Its digest is computed over a generated password, so the name
# is a sensitive value and an output carrying it is rejected with "Output refers to sensitive
# values" - and marking the output sensitive would export the taint rather than remove it. The
# commands below select on a label instead, which is not derived from anything secret
# (rules.md H-2).
output "db_init_status_command" {
  value       = "kubectl -n ${var.namespace} get jobs -l app.kubernetes.io/name=${local.init_job_base_name}"
  description = "The init Jobs that have run. COMPLETIONS 1/1 is the healthy state; more than one entry means the role has been reconciled more than once, which is what a changed password or a changed script looks like. None at all, on a cluster that has been applied, means the Job was cleaned up by its TTL - which is normal"
}
output "db_init_log_command" {
  value       = "kubectl -n ${var.namespace} logs -l app.kubernetes.io/name=${local.init_job_base_name} --tail 50"
  description = "What the role reconciliation did. \"creating role\" on a first apply and \"resetting its password\" afterwards; \"waiting for postgres\" repeated means the Job is up before the database, which it retries. This is the log that was silently empty while the script was broken, because nothing ever read the postgres entrypoint's output"
}
