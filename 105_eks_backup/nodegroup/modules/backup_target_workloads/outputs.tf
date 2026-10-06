output "namespace" {
  value       = var.namespace
  description = "Namespace the namespaced objects live in, re-exposed so the verification commands and the caller read one value (rules.md B-5)"
}

output "rollout_status_command" {
  # Every Deployment that exists, joined into one command. Written from the same flags that decided
  # whether each was created, so it cannot name one that is absent.
  value = join(" && ", concat(
    var.create_efs_workload ? ["kubectl -n ${var.namespace} rollout status deployment efs --timeout=10m"] : [],
    var.create_ebs_workload ? ["kubectl -n ${var.namespace} rollout status deployment ebs --timeout=10m"] : [],
    var.create_s3_workload ? ["kubectl -n ${var.namespace} rollout status deployment s3 --timeout=10m"] : [],
    var.create_plain_workloads ? ["kubectl -n ${var.namespace} rollout status deployment deployment-app --timeout=10m"] : [],
  ))
  description = "Waits for every Deployment this module created. A rollout that never completes is usually a claim that has not bound, which the next command shows"
}

output "claim_status_command" {
  value       = "kubectl -n ${var.namespace} get pvc,pv"
  description = "Bound is the only state worth seeing. The EBS claim stays Pending until a pod is scheduled, which is WaitForFirstConsumer working rather than failing"
}

output "volume_contents_command" {
  value = join("; ", concat(
    var.create_efs_workload ? ["kubectl -n ${var.namespace} exec deployment/efs -- tail -3 /data/out"] : [],
    var.create_ebs_workload ? ["kubectl -n ${var.namespace} exec deployment/ebs -- tail -3 /data/out.txt"] : [],
    var.create_s3_workload ? ["kubectl -n ${var.namespace} exec deployment/s3 -- ls /data"] : [],
  ))
  description = "What is actually on each volume. This is the thing a restore is checked against - a recovery point taken before these pods wrote anything restores an empty volume, which is exactly what the original produced"
}

output "backup_target_summary_command" {
  value       = "kubectl -n ${var.namespace} get deployments,pods,pvc,serviceaccounts,roles,rolebindings && kubectl get clusterroles,clusterrolebindings -l '!kubernetes.io/bootstrapping' --field-selector metadata.name=${var.rbac_name}"
  description = "Everything in the cluster the backup is meant to capture. Worth running before starting a backup job, because a recovery point only contains what existed when it was taken"
}

output "rbac_name" {
  value       = var.rbac_name
  description = "Name shared by the five RBAC objects, re-exposed so the caller's commands do not restate it (rules.md B-5)"
}
