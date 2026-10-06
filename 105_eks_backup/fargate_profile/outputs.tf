# Every value here is a projection of local.outputs in main.tf, which the README written onto the
# workbench renders from the same map - so no value expression exists twice (rules.md B-5/H-2).
#
# The descriptions are the one thing that cannot be projected: Terraform does not allow an expression
# in an output description ("Variables not allowed"), so the wording is repeated here as a literal
# while the values are not.

output "vscode_url" {
  value       = local.outputs.vscode_url.value
  description = "Open the IDE here and run every command below from its terminal. The kubeconfig already has both clusters as contexts named primary and secondary"
}

output "primary_cluster_name" {
  value       = local.outputs.primary_cluster_name.value
  description = "The cluster the backup is taken of. Everything Terraform creates inside a cluster is here"
}

output "secondary_cluster_name" {
  value       = local.outputs.secondary_cluster_name.value
  description = "Deliberately empty - no addons, no capacity, no objects. AWS Backup writes into it, and anything Terraform put there would be a second owner of what a restore is about to replace"
}

output "backup_vault_name" {
  value       = local.outputs.backup_vault_name.value
  description = "Name-prefixed rather than fixed. The original hardcoded the vault as \"eks\", and a vault cannot be renamed - so a second copy of the project in one account collided permanently"
}

output "backup_role_arn" {
  value       = local.outputs.backup_role_arn.value
  description = "The role AWS Backup assumes. It carries the S3 backup and restore policies as well as the EKS ones, because an EKS recovery point has a child for every attached volume - including a bucket"
}

output "workloads_ready_command" {
  value       = local.outputs.workloads_ready_command.value
  description = "Three volume-backed Deployments, a bare Pod, a node-selected Deployment and five RBAC objects. None of these existed in the original: every manifest was applied by a user-data script that stopped at an `exec bash` several lines earlier"
}

output "claims_bound_command" {
  value       = local.outputs.claims_bound_command.value
  description = "AWS Backup captures a volume only when its claim is provisioned by a CSI driver, which a statically provisioned EFS volume still is. Static is the only option here: AWS supports no dynamic provisioning with Fargate nodes, so the efs-ap StorageClass the other variants use would leave this claim Pending forever"
}

output "volume_contents_command" {
  value       = local.outputs.volume_contents_command.value
  description = "What a restore is checked against. A recovery point taken before these pods wrote anything restores empty volumes, which is exactly what the original produced"
}

output "start_backup_command" {
  value       = local.outputs.start_backup_command.value
  description = "The apply already started one of these and waited for it, so the vault holds a recovery point before anyone runs anything - the original did the same, and the scheduled plan is for keeping backups happening rather than for the first one. Run this again after changing the workloads, to get a second recovery point to compare a restore against"
}

output "recovery_points_command" {
  value       = local.outputs.recovery_points_command.value
  description = "One EKS backup produces several rows: a composite parent for the cluster state and a child for each attached volume - on this variant that is one EFS child, since a Fargate pod has no block device and no bucket mount. The parent is the ARN a restore takes, and it is the one containing \"composite:eks\""
}

output "restore_metadata_existing" {
  value       = local.outputs.restore_metadata_existing.value
  description = "The metadata document with everything Terraform knows already filled in. Add the recovery point ARN, and a nestedRestoreJobs entry per child recovery point - see manifests/ in this project for a captured example of the finished article. The original left two placeholder markers here"
}

output "restore_metadata_new" {
  value       = local.outputs.restore_metadata_new.value
  description = "The same call with newCluster true. This document also carries the cluster role, VPC config and node group definition, which is why a new-cluster restore can recreate managed node groups, Fargate profiles, addons and Pod Identity associations - and why it cannot recreate the OIDC provider or any ECR image"
}

output "restore_result_command" {
  value       = local.outputs.restore_result_command.value
  description = "Run against the secondary context. Services and Ingresses are never restored, and pods matching a nodeSelector the target cluster's nodes do not carry stay Pending - both are expected"
}

output "skipped_objects_command" {
  value       = local.outputs.skipped_objects_command.value
  description = "A restore job reports COMPLETED even when it skipped objects. The list exists only as vault notifications, which is what the topic and queue are for - and the queue policy that lets SNS deliver to it was missing in the original, so the queue stayed empty"
}

output "backup_plan_id" {
  value       = local.outputs.backup_plan_id.value
  description = "A scheduled plan covering the primary cluster, which the original did not have: it started one job from a shell and left it there, so the cluster had exactly one recovery point for as long as it existed. The plan is what makes a backup a property of the configuration; the job the apply starts is what makes the demo runnable before the plan's first 03:00 UTC run"
}

output "update_kubeconfig_command" {
  value       = local.outputs.update_kubeconfig_command.value
  description = "User data already wrote both contexts. Re-run these if the kubeconfig is ever lost"
}
