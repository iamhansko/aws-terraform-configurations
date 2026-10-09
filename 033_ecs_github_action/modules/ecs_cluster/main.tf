# The cluster on its own.
#
# aws_ecs_cluster_capacity_providers is deliberately not here, even though it is a property of this
# cluster. It names the EC2 capacity provider, which is built from the Auto Scaling group in
# ecs_asg_capacity_provider, so putting it here would mean this module taking the provider name as an
# input - and that is a cycle on destroy as well as an awkward argument: the cluster would have to be
# destroyed before the provider it names. It lives next to the provider instead, which is where the
# ordering already works out (see that module).
resource "aws_ecs_cluster" "ecs_cluster" {
  name = var.name
  setting {
    name  = "containerInsights"
    value = var.container_insights
  }
}
