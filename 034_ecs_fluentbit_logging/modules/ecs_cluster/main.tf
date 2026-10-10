# The cluster on its own, with neither its capacity nor its workload in it.
#
# That split is not tidiness, it is a dependency cycle avoided. The container instances have to be told
# which cluster to join - the launch template userdata writes ECS_CLUSTER into /etc/ecs/ecs.config - and
# the cluster has to be told which capacity provider to default to. Putting the cluster, the Auto Scaling
# group and the association in one module makes that a cycle between resources Terraform cannot order.
# Keeping the cluster alone means capacity reads the cluster name as a variable, and the association is
# declared next to the capacity provider it names.
resource "aws_ecs_cluster" "ecs_cluster" {
  name = var.name
  setting {
    name  = "containerInsights"
    value = var.container_insights
  }
}
