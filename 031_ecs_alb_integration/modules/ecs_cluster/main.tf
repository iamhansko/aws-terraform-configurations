resource "aws_ecs_cluster" "ecs_cluster" {
  name = var.name
  # Stated rather than left to the account default, which the _monolithic template did by declaring nothing
  # but a name. The two widgets on this project's dashboard read CPUUtilization and MemoryUtilization from
  # the AWS/ECS namespace, which ECS publishes for every service whatever this is set to - so "disabled"
  # costs the dashboard nothing. It is the ECS/ContainerInsights namespace, per task and per container, that
  # needs "enhanced", and nothing here reads it.
  setting {
    name  = "containerInsights"
    value = var.container_insights
  }
}
