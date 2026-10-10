resource "aws_ecs_cluster" "cluster" {
  # CloudFormation generated this name; Terraform requires one, so the caller derives it from the project
  # name as the _monolithic template did from the stack name.
  name = var.name
  setting {
    name  = "containerInsights"
    value = var.container_insights
  }
}
# FARGATE as the default, with FARGATE_SPOT available, as the _monolithic template had it. The services here
# name launch_type FARGATE themselves; the default strategy is for tasks run by hand.
resource "aws_ecs_cluster_capacity_providers" "cluster" {
  cluster_name       = aws_ecs_cluster.cluster.name
  capacity_providers = ["FARGATE", "FARGATE_SPOT"]
  default_capacity_provider_strategy {
    capacity_provider = "FARGATE"
    weight            = 1
  }
}
