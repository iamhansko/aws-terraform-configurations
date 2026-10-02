# Auto Scaling lifecycle hooks on the node groups' Auto Scaling groups.
#
# These are what make queue mode worth its extra infrastructure. A terminate hook holds the
# instance in Terminating:Wait and publishes an event, so the handler gets a chance to drain
# the node before the instance is gone - and then calls CompleteLifecycleAction to release it
# rather than letting the heartbeat expire. Without the hook a scale-in or an instance refresh
# terminates the node with no notice of any kind, which is precisely the gap IMDS mode cannot
# cover: an instance cannot learn from its own metadata that its Auto Scaling group has decided
# to replace it.
#
# Where the ASG names come from is worth stating, because the _monolithic template went a long
# way round. It shipped a Lambda-backed CloudFormation custom resource whose whole job was to
# call eks:DescribeNodegroup and read resources.autoScalingGroups[0].name, complete with its own
# IAM role, an inline policy and a Python handler importing cfnresponse. The Terraform provider
# exposes exactly that field on aws_eks_node_group, so the Lambda, its role, its policy and its
# source archive are all deleted rather than converted - and the conversion could not have
# worked anyway: cfnresponse only exists inside a CloudFormation-invoked Lambda, and the
# aws_lambda_invocation the generator produced passed its inputs at the top level while the
# handler read them from event["ResourceProperties"].
resource "aws_autoscaling_lifecycle_hook" "terminating" {
  for_each = var.autoscaling_group_names

  name                   = "${each.key}-terminating"
  autoscaling_group_name = each.value
  lifecycle_transition   = "autoscaling:EC2_INSTANCE_TERMINATING"
  # CONTINUE, as the _monolithic template had it: if nothing completes the action within the
  # heartbeat, the termination proceeds anyway. ABANDON here would leave a failed scale-in
  # instead, which is the wrong trade - a node that was not drained in time still has to go.
  default_result    = var.terminating_default_result
  heartbeat_timeout = var.heartbeat_timeout_seconds
}
# The launching hook is the counterpart, and the one whose default_result matters more:
# ABANDON means an instance that never reports healthy is terminated rather than joining the
# group. The handler does not act on launching events - this is Auto Scaling guarding itself.
resource "aws_autoscaling_lifecycle_hook" "launching" {
  for_each = var.create_launching_hooks ? var.autoscaling_group_names : {}

  name                   = "${each.key}-launching"
  autoscaling_group_name = each.value
  lifecycle_transition   = "autoscaling:EC2_INSTANCE_LAUNCHING"
  default_result         = var.launching_default_result
  heartbeat_timeout      = var.heartbeat_timeout_seconds
}
