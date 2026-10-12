# The cluster on its own, with neither its capacity nor its workload in it.
#
# The GPU instances have to be told which cluster to join - their user data writes ECS_CLUSTER into
# /etc/ecs/ecs.config - and the cluster has to be told about their capacity provider. Keeping the cluster
# alone lets the capacity module read its name and declare the association itself, which is the order the
# two have to be created in.
resource "aws_ecs_cluster" "cluster" {
  name = var.name

  # The blueprint's container_insights=True.
  setting {
    name  = "containerInsights"
    value = var.container_insights
  }
}
