# Pre-creates a load balancer carrying the three tags the AWS Load Balancer
# Controller stamps on the ones it owns, so when the workload's Ingress (or
# Service) is reconciled the controller finds this load balancer and adopts it
# instead of provisioning a second one. That is the "sync" this variant
# demonstrates: the load balancer is a Terraform resource with a stable ARN and
# reviewable configuration, while listeners and target groups stay the
# controller's job.
#
# All three tags have to match for adoption to happen, and the scheme and type
# have to agree with the workload's annotations. A mismatch is not an error - it
# just means the controller creates its own load balancer alongside this one
# (rules.md G-3).
locals {
  # ingress.k8s.aws/* for a load balancer fronting an Ingress,
  # service.k8s.aws/* for one fronting a Service of type LoadBalancer.
  controller_tags = {
    "elbv2.k8s.aws/cluster"                       = var.cluster_name
    "${var.resource_tag_prefix}.k8s.aws/resource" = "LoadBalancer"
    "${var.resource_tag_prefix}.k8s.aws/stack"    = var.stack
  }
}
resource "aws_lb" "synced_load_balancer" {
  name                       = var.name
  name_prefix                = var.name == null ? "k8s-" : null
  load_balancer_type         = var.load_balancer_type
  internal                   = var.internal
  subnets                    = var.subnet_ids
  security_groups            = length(var.security_group_ids) > 0 ? var.security_group_ids : null
  enable_deletion_protection = var.enable_deletion_protection

  tags = merge(local.controller_tags, var.additional_tags)

  lifecycle {
    # The controller mutates the load balancer once it adopts it - attributes,
    # listeners and target group wiring. Ignoring these keeps every subsequent
    # terraform plan from proposing to undo the controller's work - including the
    # tags above, which are what adoption matches on (rules.md G-3).
    ignore_changes = [security_groups, subnets, tags, tags_all]
  }
}
