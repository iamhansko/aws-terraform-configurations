# Every value here is a projection of local.outputs in main.tf, which the README written onto the
# workbench renders from the same map - so no value expression exists twice (rules.md B-5/H-2).
#
# The descriptions are the one thing that cannot be projected: Terraform does not allow an expression
# in an output description ("Variables not allowed"), so the wording is repeated here as a literal
# while the values are not.

output "vscode" {
  value       = local.outputs.vscode.value
  description = "Open the IDE here and run every command below from its terminal. kubectl, eksctl and helm are already installed and the kubeconfig already points at the cluster"
}

output "eks_cluster_name" {
  value       = local.outputs.eks_cluster_name.value
  description = "Name of the EKS cluster AWS Batch submits jobs into"
}

output "eks_cluster_endpoint" {
  value       = local.outputs.eks_cluster_endpoint.value
  description = "API server endpoint of the EKS cluster"
}

output "batch_job_queue_arn" {
  value       = local.outputs.batch_job_queue_arn.value
  description = "The queue a submitted job lands in. Its compute environment is the EKS cluster, so a job here becomes a pod rather than an EC2 instance"
}

output "batch_job_definition_arn" {
  value       = local.outputs.batch_job_definition_arn.value
  description = "What a submitted job runs. The namespace it targets has to exist and carry the RBAC the Batch service-linked role is mapped to, which is what the batch module creates"
}

output "submit_job_command" {
  value       = local.outputs.submit_job_command.value
  description = "Names the queue and definition above. A job stuck in RUNNABLE usually means the namespace mapping is missing rather than that there is no capacity"
}

output "job_status_command" {
  value       = local.outputs.job_status_command.value
  description = "SUBMITTED to RUNNABLE to STARTING to RUNNING to SUCCEEDED. Anything that stops at RUNNABLE is a placement problem, and the reason is in the queue's status reason rather than in the pod"
}

output "job_pod_command" {
  value       = local.outputs.job_pod_command.value
  description = "AWS Batch creates the pod itself, so it is not declared anywhere in this configuration. It appears in the namespace the job definition names"
}

output "namespace_rbac_command" {
  value       = local.outputs.namespace_rbac_command.value
  description = "AWS Batch reaches the cluster as AWSServiceRoleForBatch, a service-linked role. Access entries do not accept those, so the mapping is in the aws-auth ConfigMap instead (rules.md E-6) - and the ARN in it has its path stripped, which the IAM authenticator requires"
}

output "update_kubeconfig_command" {
  value       = local.outputs.update_kubeconfig_command.value
  description = "User data already ran this, so kubectl works out of the box. Re-run it if the kubeconfig is ever lost"
}
