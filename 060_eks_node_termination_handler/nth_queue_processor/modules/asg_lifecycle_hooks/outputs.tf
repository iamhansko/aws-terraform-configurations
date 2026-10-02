output "autoscaling_group_names" {
  value       = var.autoscaling_group_names
  description = "The groups hooks were placed on, keyed by the caller's label. Re-exposed so the caller's diagnostic commands name the same groups this module hooked (rules.md B-5)"
}
output "terminating_hook_names" {
  value       = { for key, hook in aws_autoscaling_lifecycle_hook.terminating : key => hook.name }
  description = "Terminating hook name per group. These are the hooks that give the handler its chance to drain, so their presence is the first thing to check when a scale-in took a node without one"
}
output "describe_hooks_command" {
  value       = "aws autoscaling describe-lifecycle-hooks --auto-scaling-group-name ${values(var.autoscaling_group_names)[0]}"
  description = "The hooks on one group, with their transitions and heartbeats. Substitute another group name from the list above for the others"
}
output "scale_in_command" {
  value       = "aws autoscaling set-desired-capacity --auto-scaling-group-name ${values(var.autoscaling_group_names)[0]} --desired-capacity 1 --honor-cooldown"
  description = "Forces a scale-in, which is how to exercise the terminating hook without waiting for a spot interruption. This is the event IMDS mode cannot see at all: the instance is not being reclaimed by EC2, its own group is removing it"
}
