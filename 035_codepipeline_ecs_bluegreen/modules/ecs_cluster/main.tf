# The cluster on its own, with neither its capacity nor its workload in it.
#
# That split is not tidiness, it is a dependency cycle avoided. The container instances have to be told
# which cluster to join - the launch template userdata writes ECS_CLUSTER into /etc/ecs/ecs.config - and
# the cluster has to be told which capacity provider to default to, while the capacity provider is
# built on the Auto Scaling group those instances come from. Declaring all three in one module makes
# that a cycle Terraform cannot order. Keeping the cluster alone means capacity reads the cluster name,
# and the association that links the two is declared next to the provider it names.
resource "aws_ecs_cluster" "ecs_cluster" {
  name = var.name
  setting {
    name  = "containerInsights"
    value = var.container_insights
  }
  configuration {
    execute_command_configuration {
      logging = var.execute_command_logging
    }
  }
}
