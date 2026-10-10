# Plain output blocks, with their value expressions written here rather than projected out of a
# local.outputs map in main.tf. That is deliberate, and this note exists because the rest of this
# repository does the opposite.
#
# rules.md H-2 requires the map, and requires every output to be mirrored into /home/ec2-user/README.md
# on the workbench - but it applies to a root that has a code-server workbench, because the point of the
# map is that a person working inside a browser IDE has no terraform output to ask. This project has no
# workbench. Its aws_instance is a one-shot builder: its userdata installs docker, writes a Go program and
# a Dockerfile, pushes an image to ECR and an archive to S3, drops a completion marker and is never opened
# again. There is no code-server on it, nothing serves a README from it, and the person running this
# project reads these values from the terminal they ran apply in.
#
# So the map would be a map of one reader, and the association that writes the README would be a second
# SSM step whose only purpose is to satisfy a rule that does not apply. 014_basic_ec2 and
# 015_basic_vpc_and_subnets are the other two roots in this repository that skip it, for the same reason.
#
# If a workbench is ever added here, this file has to become a projection of that map - not a second,
# diverging list.
#
# The _monolithic template had exactly one output, "api". It is the first one below.
output "api" {
  value       = "${module.application_load_balancer.url}${var.dummy_path}"
  description = "The demo URL, and the one output the _monolithic template had. Returns the dummy route's body - \"BLUE\" from the seed image - and changing that body in the uploaded archive and re-running the pipeline is how a blue/green cutover is observed from outside"
}
output "load_balancer_url" {
  value       = module.application_load_balancer.url
  description = "Base URL of the ALB. Its listener is the field CodeDeploy rewrites on every deployment, which is why the live target group is read from the listener rather than from Terraform state"
}
output "health_url" {
  value       = "${module.application_load_balancer.url}${var.health_check_path}"
  description = "The path both target groups health-check. A 200 here while the dummy route fails means the task is running and the application is not serving what the demo expects"
}
# --- The demo, in order -----------------------------------------------------------------------------------
output "build_directory" {
  value       = module.bastion_ec2.build_directory
  description = "1. Where the builder assembled the Go program, the Dockerfile and the archive. Connect with the SSH command below, or with Session Manager, and edit main.go here to change what the dummy route returns"
}
output "reupload_command" {
  value       = module.bastion_ec2.reupload_command
  description = "2. Run from the build directory, this uploads the archive again and that write is what starts a pipeline run. It is also the reliable way to trigger the first deployment: the upload the userdata performs happens during apply and can land before the CloudTrail trail is recording, in which case nothing was triggered"
}
output "pipeline_status_command" {
  value       = module.code_pipeline.pipeline_status_command
  description = "3. The three stages and which one is running. Source reads the archive, Build registers a task definition revision and writes the appspec, Deploy hands it to CodeDeploy"
}
output "build_log_command" {
  value       = module.code_build_project.build_log_command
  description = "4. Live output from the build. This is where the image tag is stamped from the clock and where a permission the scoped build role is missing names the call it needed"
}
output "deployment_status_command" {
  value       = module.code_deploy.deployment_status_command
  description = "5. The deployment itself. errorInformation is where a replacement task set that could not be placed shows up, and rollbackInfo is where an automatic rollback says what triggered it"
}
output "target_set_command" {
  value       = module.code_deploy.target_set_command
  description = "6. The two task sets during a cutover, one PRIMARY and one ACTIVE. One left behind afterwards is a deployment that was stopped rather than completed"
}
output "target_health_command" {
  value       = module.application_load_balancer.target_health_command
  description = "7. Exactly one target group holds healthy targets between deployments, and both do briefly during a cutover. Targets stuck unhealthy with Target.Timeout is a security group path problem rather than an application one - which is what the _monolithic template's missing egress rules produced"
}
output "start_pipeline_command" {
  value       = module.code_pipeline.start_pipeline_command
  description = "Starts a run without uploading anything, for the case where the EventBridge trigger is what is being investigated rather than the pipeline"
}
# --- Diagnostics ------------------------------------------------------------------------------------------
output "builder_log_command" {
  value       = module.bastion_ec2.build_log_command
  description = "The builder's own cloud-init output. The first place to look when the apply fails on the image verification association, because that association only reports which of its three phases timed out"
}
output "list_images_command" {
  value       = module.ecr_repository.list_images_command
  description = "One image from the builder's seed push, and one per pipeline run after that, each tagged with the time the build ran. An empty list means the builder never got as far as pushing"
}
output "list_task_definitions_command" {
  value       = "aws ecs list-task-definitions --family-prefix ${module.ecs_service.task_definition_family}"
  description = "Revision 1 is Terraform's. Every later one was registered by a pipeline run, which is why the service's task_definition field is deliberately not tracked"
}
output "service_status_command" {
  value       = module.ecs_service.service_status_command
  description = "Desired against running task counts and the rollout state"
}
output "service_events_command" {
  value       = module.ecs_service.service_events_command
  description = "The service's own account of what it has been doing. \"unable to place a task because no container instance met all of its requirements\" during a cutover is the capacity provider needing a new instance rather than a placement constraint"
}
output "stopped_task_reason_command" {
  value       = module.ecs_service.stopped_task_reason_command
  description = "Why the most recently stopped task stopped. CannotPullContainerError here means the image is missing; ResourceInitializationError means the task could not reach ECR or CloudWatch Logs at all"
}
output "container_log_command" {
  value       = module.ecs_service.container_log_command
  description = "The application's own output. The _monolithic template created this log group and then named it as a literal inside the buildspec, so renaming the group would have left the pipeline's revisions logging to one that does not exist"
}
output "container_instances_command" {
  value       = module.ecs_cluster.container_instances_command
  description = "An empty list while the Auto Scaling group reports healthy instances means an instance that cannot reach the ECS endpoint - it never becomes an ECS object that could report a problem, and the service blames placement instead"
}
output "container_instance_status_command" {
  value       = module.ecs_asg_capacity_provider.container_instance_status_command
  description = "The instances from the Auto Scaling group's side. The group is 100% spot by default, so an instance disappearing mid-demo with its task rescheduled elsewhere is the configuration working rather than a fault"
}
output "scaling_activities_command" {
  value       = module.ecs_asg_capacity_provider.scaling_activities_command
  description = "Why the group launched or terminated an instance. DesiredCapacity differing from what the configuration declares is expected rather than drift: ECS managed scaling owns that field"
}
output "service_placement_failure_command" {
  value       = module.ecs_cluster.service_placement_failure_command
  description = "Placement failures on their own, separated from the rest of the service's events"
}
output "listener_rules_command" {
  value       = module.application_load_balancer.listener_rules_command
  description = "The listener's rules, including the user-agent rule the _monolithic template declared. A deployment rewrites both the default rule and the user-agent rule, so after one both should name the same target group; if they differ, the next deployment fails with Primary taskset target group must be behind listener"
}
output "object_check_command" {
  value       = module.code_pipeline_source_bucket.object_check_command
  description = "Whether the source archive is in the bucket, and which version is current. The bucket is versioned because a CodePipeline S3 source requires it"
}
output "artifact_list_command" {
  value       = module.code_pipeline_artifact_bucket.artifact_list_command
  description = "One artifact per stage per execution. Destroying this project deletes all of them - see bucket_force_destroy"
}
output "trail_status_command" {
  value       = module.cloudtrail.trail_status_command
  description = "Whether the trail is logging. If it is not, an upload produces no event and the pipeline never starts - and nothing reports an error, because there is nothing to report"
}
output "event_selector_command" {
  value       = module.cloudtrail.event_selector_command
  description = "The data event selector, which has to name the source object specifically. Management events alone do not see an S3 object write, which is the defect this selector exists to avoid"
}
output "event_pattern_command" {
  value       = module.s3_upload_pipeline_trigger.event_pattern_command
  description = "The EventBridge pattern matched against the CloudTrail event. It names three S3 API calls, not just PutObject: the CLI switches to a multipart upload above a size threshold and the event is then CompleteMultipartUpload"
}
output "triggered_invocations_command" {
  value       = module.s3_upload_pipeline_trigger.triggered_invocations_command
  description = "How many times the rule has matched. Zero after an upload means the pattern or the trail, not the pipeline"
}
output "failed_invocations_command" {
  value       = module.s3_upload_pipeline_trigger.failed_invocations_command
  description = "Matches the rule could not deliver. Non-zero means the rule's role cannot start the pipeline, which is an IAM problem rather than a pattern one"
}
# --- Names and addresses ----------------------------------------------------------------------------------
output "cluster_name" {
  value       = module.ecs_cluster.cluster_name
  description = "Name of the ECS cluster. The container instance launch template writes it into /etc/ecs/ecs.config, and the service, the capacity provider association and the deployment group all name it"
}
output "service_name" {
  value       = module.ecs_service.service_name
  description = "Name of the ECS service, which CodeDeploy's deployment group names and whose deployment controller is CODE_DEPLOY"
}
output "task_definition_family" {
  value       = module.ecs_service.task_definition_family
  description = "The family this apply registered revision 1 into and every pipeline run registers another into, so a deployment always moves the service forward inside one family"
}
output "capacity_provider_name" {
  value       = module.ecs_asg_capacity_provider.capacity_provider_name
  description = "Named in the appspec CodeBuild generates for the replacement task set. The _monolithic template passed the provider's ARN here, which the appspec rejects - it takes a name"
}
output "pipeline_name" {
  value       = module.code_pipeline.pipeline_name
  description = "Name of the pipeline"
}
output "code_build_project_name" {
  value       = module.code_build_project.project_name
  description = "Name of the CodeBuild project"
}
output "code_deploy_application_name" {
  value       = module.code_deploy.application_name
  description = "Name of the CodeDeploy application"
}
output "code_deploy_deployment_group_name" {
  value       = module.code_deploy.deployment_group_name
  description = "Name of the deployment group. The _monolithic template passed the resource's generated id to the pipeline's deploy action instead, which is \"<application>:<group>\" - a value CodeDeploy has no group under"
}
output "source_bucket_name" {
  value       = module.code_pipeline_source_bucket.bucket_name
  description = "Bucket the builder uploads the archive to and the pipeline's source stage reads"
}
output "source_object_key" {
  value       = module.code_pipeline_source_bucket.object_key
  description = "Key of that archive. The CloudTrail selector and the EventBridge pattern both name it, so an upload under any other key starts nothing"
}
output "artifact_bucket_name" {
  value       = module.code_pipeline_artifact_bucket.bucket_name
  description = "Bucket CodePipeline passes artifacts between stages through"
}
output "cloudtrail_logs_bucket_name" {
  value       = module.cloudtrail.logs_bucket_name
  description = "Bucket the trail writes to. Its policy is what lets cloudtrail.amazonaws.com write at all - without it CreateTrail fails outright"
}
output "ecr_repository_url" {
  value       = module.ecr_repository.repository_url
  description = "Repository the builder and CodeBuild both push to and the task definitions pull from"
}
output "seed_image_uri" {
  value       = module.ecr_repository.seed_image_uri
  description = "The tagged reference revision 1 of the task definition pulls. The verification association during apply checks this specific tag is present before the service is allowed to start"
}
output "event_rule_name" {
  value       = module.s3_upload_pipeline_trigger.event_rule_name
  description = "Name of the EventBridge rule. Managed here rather than created by the CodePipeline console, which writes an equivalent rule of its own and would leave two"
}
output "vpc_id" {
  value       = module.network.vpc_id
  description = "ID of the VPC"
}
output "public_subnet_ids" {
  value       = module.network.public_subnet_ids
  description = "The subnets the ALB and the builder sit in"
}
output "private_subnet_ids" {
  value       = module.network.private_subnet_ids
  description = "The subnets the container instances and the task interfaces sit in, reaching ECR and CloudWatch Logs through the zonal NAT gateways"
}
output "builder_instance_id" {
  value       = module.bastion_ec2.instance_id
  description = "Instance ID of the builder, for Session Manager or for reading its SSM command output"
}
output "builder_public_ip" {
  value       = module.bastion_ec2.public_ip
  description = "Public address of the builder"
}
output "private_key_command" {
  value       = module.key_pair.private_key_command
  description = "Retrieves the generated private key from Parameter Store into key.pem. CloudFormation puts a key pair it generates there, and this reproduces that"
}
output "ssh_command" {
  value       = module.bastion_ec2.ssh_command
  description = "SSH to the builder, to edit the program and re-upload. Run the command above first to get key.pem"
}
