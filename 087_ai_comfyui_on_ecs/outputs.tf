# These outputs carry their value expressions directly rather than projecting a local.outputs map. That map
# keeps a root's outputs and a README written onto a VS Code instance in step, so it applies only to roots
# declaring module "vscode_ec2" (rules.md H-2). There is no instance here.
#
# Numbered descriptions are the order to read them in after an apply.

# --- Using it -------------------------------------------------------------------------------------------

output "comfyui_url" {
  value       = module.load_balancer.url
  description = "1. ComfyUI, behind the Cognito login. The browser warns about the certificate first - it is self-signed, as the blueprint's was. After the first apply it answers 503 until the GPU instance has booted and the task passes its health check; once the instance has been stopped (idle, or Shutdown on the admin page), / shows the admin page with a Scale Up button instead"
}
output "create_user_command" {
  value       = "aws cognito-idp admin-create-user --user-pool-id ${module.cognito.user_pool_id} --username alice --user-attributes Name=email,Value=alice@example.com Name=email_verified,Value=true Name=given_name,Value=Alice Name=family_name,Value=Example --desired-delivery-mediums EMAIL"
  description = "2. Adds a user, with the example values replaced. Self sign-up is off by default, so this - or the console page below - is how the first user gets in. Cognito emails a temporary password, which the hosted UI asks to change at first sign-in"
}
output "user_management_console_url" {
  value       = module.cognito.user_management_console_url
  description = "The same thing in the console, which is what the blueprint's instructions pointed to"
}
output "set_user_password_command" {
  value       = "aws cognito-idp admin-set-user-password --user-pool-id ${module.cognito.user_pool_id} --username alice --password '<password>' --permanent"
  description = "3. Sets a user's password directly, for the user create_user_command made or any other. It is the way in when the temporary-password mail never arrives, and it resets a forgotten password too: Cognito can set a password but has no call that reads one back. Replace <password> and the username. The pool requires 12 or more characters with an upper-case letter, a digit and a symbol; lower-case is not required. The placeholder fails that policy, so running this unedited changes nothing. --permanent makes it the working password; without it the user is left FORCE_CHANGE_PASSWORD and the hosted UI asks for a new one at first sign-in. Single quotes keep the shell from reading a ! in the password, and the password is typed at the shell, so it never enters Terraform or its state. To skip the temporary-password mail, create the user with --message-action SUPPRESS in place of --desired-delivery-mediums EMAIL"
}
output "admin_url" {
  value       = "${module.load_balancer.url}/admin"
  description = "The blueprint's admin page: scale the GPU instance up, restart Docker on it, or shut it down. With auto_scale_down, the instance also stops by itself after an hour without work"
}

# --- Checking on it -------------------------------------------------------------------------------------

output "image_build_status_command" {
  value       = module.comfyui_image.build_status_command
  description = "4. The image build. The apply already waited for it; this is for when it failed - the phase says where - or was rerun by hand"
}
output "gpu_instance_activity_command" {
  value       = module.ecs_gpu_capacity.scaling_activities_command
  description = "5. Whether the GPU instance launched. The usual reasons it did not are here: no spot capacity under spot_max_price for any listed type in either zone, or a vCPU quota of zero for G instances (All G and VT Spot Instance Requests), which new accounts often have"
}
output "service_events_command" {
  value       = module.comfyui_service.service_events_command
  description = "6. The ECS service's task counts and recent events - an instance that has not registered yet, a GPU already taken, an image or volume that would not attach"
}
output "comfyui_logs_command" {
  value       = module.comfyui_service.logs_command
  description = "7. ComfyUI's own log. The first start copies the installation onto the new volume and takes a few minutes before the health check passes"
}
output "admin_status_command" {
  value       = module.admin_functions.status_command
  description = "What the /admin page shows, read by invoking its function directly - a quick way to tell a permissions problem in the functions from a login problem in front of them"
}

# --- What the blueprint reported ------------------------------------------------------------------------

output "load_balancer_dns_name" {
  value       = module.load_balancer.dns_name
  description = "The blueprint's Endpoint output"
}
output "user_pool_id" {
  value       = module.cognito.user_pool_id
  description = "The blueprint's UserPoolId output"
}
output "cognito_domain_name" {
  value       = module.cognito.domain
  description = "The blueprint's CognitoDomainName output - the hosted UI's prefix, unique per region across accounts"
}
output "cognito_user_pool_tier" {
  value       = module.cognito.user_pool_tier
  description = "The user pool's feature plan. PLUS while cognito_advanced_security_mode is not OFF - billed per monthly active user with no free tier"
}

# --- Image ----------------------------------------------------------------------------------------------

output "image_uri" {
  value       = module.comfyui_image.image_uri
  description = "The image the task runs, tagged with the hash of comfyui_image/. Editing a file there builds a new tag and rolls the task onto it on the next apply"
}
output "restart_image_build_command" {
  value       = module.comfyui_image.start_build_command
  description = "Runs the image build by hand - needed after an apply with build_image_on_apply = false. With the tag already pushed it confirms that and stops"
}

# --- Outside Terraform ----------------------------------------------------------------------------------

output "comfyui_volume_command" {
  value       = "aws ec2 describe-volumes --filters Name=tag:Name,Values=${module.comfyui_service.volume_name} --query 'Volumes[].[VolumeId,AvailabilityZone,Size,State]' --output table"
  description = "The EBS volume ComfyUI, its models and its outputs live on. The REX-Ray plugin creates it the first time the task starts, so it is not in Terraform state and terraform destroy leaves it - as deleting the blueprint's stack did. It also pins the task to its zone: an instance in the other zone cannot attach it"
}
output "delete_comfyui_volume_command" {
  value       = "aws ec2 delete-volume --volume-id $(aws ec2 describe-volumes --filters Name=tag:Name,Values=${module.comfyui_service.volume_name} --query 'Volumes[0].VolumeId' --output text)"
  description = "Deletes that volume, and with it every model and image on it. Run after terraform destroy, once the volume shows as available - until then it is attached, and the 250 GiB keeps billing after everything else is gone"
}
output "certificate_expires_at" {
  value       = module.load_balancer.certificate_expires_at
  description = "When the self-signed certificate expires. The first apply after that issues a new one"
}
output "web_acl_sampled_requests_command" {
  value       = one(module.web_acl[*].sampled_requests_command)
  description = "Requests the web ACL allowed and blocked in the last three hours, or null when no address list or rate limit is configured and there is no web ACL"
}
