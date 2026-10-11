# These outputs carry their value expressions directly rather than projecting a local.outputs map. That map
# keeps a root's outputs and a README written onto a VS Code instance in step, so it applies only to roots
# declaring module "vscode_ec2" (rules.md H-2). There is no instance here - the managed instances are ECS's,
# not a workbench.
output "shlink_domain" {
  value       = "https://${module.shlink_certificate.domain_name}"
  description = "Shlink's API and the host its short URLs are issued under. The _monolithic template's ShlinkDomain output"
}
output "shlink_web_client" {
  value       = module.web_client_alb.url
  description = "The web client, already configured with the server and the API key. The _monolithic template's ShlinkWebClient output"
}
output "shlink_api_key" {
  value       = module.shlink_configuration.api_key
  sensitive   = true
  description = "The API key both containers share. Sensitive, where the _monolithic template's ShlinkApiKey output printed it with every apply - it is an admin credential for the shortener. terraform output -raw shlink_api_key reads it"
}
output "get_api_key_command" {
  value       = module.shlink_configuration.get_api_key_command
  description = "Reads the API key from Secrets Manager instead of from Terraform state"
}
output "shorten_command" {
  value       = "curl -s -X POST https://${module.shlink_certificate.domain_name}/rest/v3/short-urls -H \"X-Api-Key: $(terraform output -raw shlink_api_key)\" -H 'Content-Type: application/json' -d '{\"longUrl\":\"https://aws.amazon.com/ecs/\"}'"
  description = "1. Shortens a URL through the API. The response's shortUrl is on the Shlink domain; opening it redirects"
}
output "health_command" {
  value       = "curl -s https://${module.shlink_certificate.domain_name}/rest/health"
  description = "2. Shlink's own health endpoint, through the alias record, the certificate and the ALB - the same path the target group checks, plus DNS and TLS"
}
output "certificate_status_command" {
  value       = module.shlink_certificate.status_command
  description = "3. Whether the certificate was issued. An apply that hangs at the certificate validation is this one in PENDING_VALIDATION, which means the hosted zone is not the one default_domain is delegated to"
}
output "container_instances_command" {
  value       = module.capacity_provider.container_instances_command
  description = "4. The managed instances ECS launched. None while tasks sit in PROVISIONING means ECS could not launch or register one"
}
output "shlink_service_events_command" {
  value       = module.shlink_service.service_events_command
  description = "5. The Shlink service's own account of what it has been doing"
}
output "shlink_stopped_task_reason_command" {
  value       = module.shlink_service.stopped_task_reason_command
  description = "6. Why Shlink tasks stopped. An EFS mount timeout is the NFS path; a secret ResourceInitializationError is the execution role"
}
output "web_client_service_events_command" {
  value       = module.web_client_service.service_events_command
  description = "7. The web client service's own account of what it has been doing"
}
output "efs_mount_targets_command" {
  value       = module.shlink_efs.mount_targets_command
  description = "8. The mount target in each zone. Shlink's data lives here, and terraform destroy deletes it - only AWS Backup's recovery points survive"
}
output "cluster_name" {
  value       = module.ecs_cluster.cluster_name
  description = "Name of the ECS cluster"
}
output "capacity_provider_name" {
  value       = module.capacity_provider.capacity_provider_name
  description = "Name of the managed instances capacity provider both services place through"
}
output "teardown_note" {
  value       = "terraform destroy first runs ${module.drain_on_destroy.function_name}, which scales both services to zero and waits until no managed instance is registered; if it times out, the destroy stops there. The EFS file system is then deleted with Shlink's data - restore from AWS Backup if it is needed"
  description = "What terraform destroy does that a plain destroy would not, and what it deletes. The _monolithic template put prevent_destroy on the file system, which stopped every destroy outright instead"
}
output "drain_log_command" {
  value       = module.drain_on_destroy.log_tail_command
  description = "What the drain did during the last destroy"
}
