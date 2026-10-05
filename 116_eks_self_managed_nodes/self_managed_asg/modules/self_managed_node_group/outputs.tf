output "autoscaling_group_name" {
  value       = aws_autoscaling_group.node.name
  description = "Name of the Auto Scaling group, for the command that scales it by hand"
}

output "autoscaling_group_arn" {
  value       = aws_autoscaling_group.node.arn
  description = "ARN of the Auto Scaling group"
}

output "launch_template_id" {
  value       = aws_launch_template.node.id
  description = "ID of the launch template the group uses"
}

output "launch_template_latest_version" {
  value       = aws_launch_template.node.latest_version
  description = "Latest launch template version. The group is pinned to it, so a template change plus an instance refresh is how a new AMI or a changed NodeConfig reaches the nodes"
}

output "node_role_arn" {
  value       = aws_iam_role.node.arn
  description = "ARN of the nodes' IAM role, mapped into system:nodes by the EC2_LINUX access entry this module creates"
}

output "node_role_name" {
  value       = aws_iam_role.node.name
  description = "Name of the nodes' IAM role, for a caller that has to attach another policy to it"
}

output "max_pods" {
  value       = var.max_pods
  description = "Pod ceiling written into each node's kubelet configuration, re-exposed so a verification command does not restate it (rules.md B-5)"
}

output "desired_capacity" {
  value       = var.desired_capacity
  description = "Instances the group was created with. Not what it currently holds - that is ignored after creation (rules.md E-8)"
}

output "instances_command" {
  value       = "aws autoscaling describe-auto-scaling-groups --auto-scaling-group-names ${aws_autoscaling_group.node.name} --query 'AutoScalingGroups[0].Instances[].[InstanceId,LifecycleState,HealthStatus,AvailabilityZone]' --output table"
  description = "Command that shows the group's instances and their lifecycle state. InService instances that are absent from kubectl get nodes mean the kubelet was refused - the access entry or the NodeConfig is wrong, and the group reports healthy either way"
}

output "scale_command" {
  value       = "aws autoscaling set-desired-capacity --auto-scaling-group-name ${aws_autoscaling_group.node.name} --desired-capacity ${var.max_size}"
  description = "Command that scales the group to its maximum. Terraform ignores desired_capacity after creation, so this does not fight the next plan (rules.md E-8)"
}

output "bootstrap_log_command" {
  value       = "aws ssm start-session --target $(aws autoscaling describe-auto-scaling-groups --auto-scaling-group-names ${aws_autoscaling_group.node.name} --query 'AutoScalingGroups[0].Instances[0].InstanceId' --output text) --document-name AWS-StartInteractiveCommand --parameters command='sudo journalctl -u nodeadm-config -u nodeadm-run --no-pager | tail -50'"
  description = "Command that reads nodeadm's log on the group's first instance through Session Manager, which is where a rejected NodeConfig is explained. There is no other place to look: a self-managed group reports nothing to EKS"
}
