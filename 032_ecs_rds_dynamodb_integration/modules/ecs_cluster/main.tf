# The cluster on its own, with neither its capacity nor its workload in it.
#
# That split avoids a dependency cycle rather than being tidiness. The container instances have to be told
# which cluster to join - the launch template userdata writes ECS_CLUSTER into /etc/ecs/ecs.config - and the
# cluster has to be told which capacity provider to default to. Declaring the cluster, the Auto Scaling
# group and the association together makes that a cycle; keeping the cluster alone means capacity reads the
# cluster name, and the association lives next to the capacity provider it names.
resource "aws_ecs_cluster" "ecs_cluster" {
  name = var.name
  setting {
    name  = "containerInsights"
    value = var.container_insights
  }
}
