# The cluster on its own, with neither its capacity nor its workload in it.
#
# That split is not tidiness, it is a dependency cycle avoided. The container instances have to be told
# which cluster to join - the launch template userdata writes ECS_CLUSTER into /etc/ecs/ecs.config - and
# the cluster has to be told which capacity provider to default to. Declaring the cluster, the Auto
# Scaling group and the association in one module makes that a cycle between resources Terraform cannot
# order; keeping the cluster alone means capacity reads the cluster name and the association is declared
# next to the capacity provider that it names. The _monolithic template had the same shape and got away
# with it only because aws_ecs_cluster_capacity_providers is a separate resource that breaks the cycle.
resource "aws_ecs_cluster" "ecs_cluster" {
  name = var.name
  setting {
    name  = "containerInsights"
    value = var.container_insights
  }
  # The namespace a Service Connect configuration joins when it names none, which is how the
  # _monolithic template of 085_ecs_service_connect wired both of its services to one namespace. An
  # object rather than a bare ARN so that whether the block exists is known at plan even though the ARN
  # is not - a null test on an unknown string would leave the block count itself unknown.
  dynamic "service_connect_defaults" {
    for_each = var.service_connect_defaults == null ? [] : [var.service_connect_defaults]
    content {
      namespace = service_connect_defaults.value.namespace
    }
  }
}
