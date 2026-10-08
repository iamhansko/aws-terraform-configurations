# These outputs carry their value expressions directly rather than projecting a local.outputs map.
#
# That map exists to keep a root's outputs and the README written onto a VS Code instance from drifting
# apart, so it applies only to roots that declare module "vscode_ec2" (rules.md H-2). The instance here is
# an image builder: it installs docker, builds one image, pushes it and is then idle. It runs no
# code-server, no SSM association writes a README onto it, and nothing is meant to be read from its
# filesystem - the commands below are run from wherever terraform was run. So there is no second copy of
# these values to keep in step.
#
# Several of the values this project produces are not Terraform's to know: which instances registered,
# where the two tasks landed, what the container wrote. Those are verification commands rather than
# omitted outputs, which is also how the load balancer addresses in rules.md G-1 and the distribution
# status in 097_cloudfront_s3_static_website are handled.
output "cluster_name" {
  value       = module.ecs_cluster.cluster_name
  description = "Name of the ECS cluster"
}
output "service_name" {
  value       = module.ecs_service.service_name
  description = "Name of the ECS service keeping the test tasks running"
}
output "task_definition_arn" {
  value       = module.ecs_service.task_definition_arn
  description = "Task definition revision this apply registered, revision number included"
}
output "image_uri" {
  value       = module.ecr_repository.image_uri
  description = "The one image reference in this project: what the builder tags and pushes, and what the task definition pulls. Both read it from the repository module so the tag cannot differ between them (rules.md B-5)"
}
output "host_volume_path" {
  value       = module.ecs_service.host_volume_path
  description = "Directory on the container instance that the task bind-mounts. This is the subject of the project - the files written here belong to the instance, outlive the task, and disappear with the instance, which on an entirely spot Auto Scaling group happens without warning"
}
output "container_mount_path" {
  value       = module.ecs_service.container_mount_path
  description = "Path inside the container the host directory appears at, which is also where the built image's test script writes. If this and the script disagree the container writes into its own layer, the task stays healthy, and the host directory stays empty"
}
output "builder_instance_id" {
  value       = module.image_builder_ec2.instance_id
  description = "ID of the image builder instance"
}
output "container_instance_asg_name" {
  value       = module.ecs_asg_capacity_provider.auto_scaling_group_name
  description = "Generated name of the container instance Auto Scaling group"
}
output "capacity_provider_name" {
  value       = module.ecs_asg_capacity_provider.capacity_provider_name
  description = "Name of the capacity provider the cluster defaults to and the service places through"
}
output "nat_gateway_public_ips" {
  value       = module.network.nat_gateway_public_ips
  description = "Addresses the container instances appear as from outside, one per zone of the single regional NAT gateway"
}
output "availability_zones" {
  value       = module.network.availability_zones
  description = "The two zones the subnets span, which is what the service's first placement strategy spreads across"
}
output "private_key_command" {
  value       = module.key_pair.private_key_command
  description = "Retrieves the generated SSH private key from Parameter Store. No security group here opens port 22, so this is for the case where the SSM agent is what is broken"
}
# --- Verification, in the order worth running it ---------------------------------------------------
output "image_check_command" {
  value       = module.ecr_repository.list_images_command
  description = "1. Whether the builder produced anything. An empty table means the image was never pushed, and nothing in ECS will say so more clearly than this - the service just reports CannotPullContainerError. If this is empty, builder_log_command has the reason"
}
output "builder_log_command" {
  value       = module.image_builder_ec2.build_log_command
  description = "2. The end of the builder's cloud-init log. The userdata runs without set -e, so a failed dnf, docker login, build or push leaves no trace in any AWS API: the instance still reports running and the completion marker is still written. This is the only place that failure is recorded"
}
output "container_instance_check_command" {
  value       = module.ecs_asg_capacity_provider.container_instance_status_command
  description = "3. Which container instances registered and whether their agent is connected. Instances launched but missing here is the signature of an instance that cannot reach the ECS endpoint - the revoked egress rule the modules describe, or a missing route to the NAT gateway"
}
output "scaling_activities_command" {
  value       = module.ecs_asg_capacity_provider.scaling_activities_command
  description = "4. The Auto Scaling group's recent activities. A group that is 100 percent spot reports a failure to get capacity here and nowhere else; apply will have succeeded regardless"
}
output "service_status_command" {
  value       = module.ecs_service.service_status_command
  description = "5. Desired against running task counts and the rollout state"
}
output "service_events_command" {
  value       = module.ecs_service.service_events_command
  description = "6. The service's own account of what it has been trying to do. Nearly every failure in this project surfaces here rather than in Terraform: no instance meeting the task's requirements is capacity or memory, a repeating stopped-task message is the image"
}
output "stopped_task_reason_command" {
  value       = module.ecs_service.stopped_task_reason_command
  description = "7. Why stopped tasks stopped. A manifest-not-found reason means the image was never pushed; one naming a platform means it was built on the wrong architecture"
}
output "task_placement_command" {
  value       = module.ecs_service.running_task_placement_command
  description = "8. Where the running tasks ended up. Two tasks, two zones, two instance ARNs is both placement strategies working - which with host networking and a shared bind mount is what keeps the two from writing into the same host directory"
}
output "container_log_command" {
  value       = module.ecs_service.container_log_command
  description = "9. The container's output as it runs. This is the result the project exists to show: a dd throughput line and a disk usage figure once a second, the usage climbing and then flattening as the retention loop deletes the oldest files"
}
output "host_volume_contents_command" {
  value       = module.ecs_service.host_volume_contents_command
  description = "10. The bind mount seen from the host. This is the check that distinguishes a real bind mount from a container writing into its own layer: the files are present on the instance and df shows the instance's root volume filling"
}
