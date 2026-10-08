resource "aws_ecs_cluster" "ecs_cluster" {
  # CloudFormation generated this name; Terraform requires one, so the caller derives it from the project
  # name as the _monolithic template did from the stack name.
  name = var.name
  setting {
    name  = "containerInsights"
    value = var.container_insights
  }
  # ECS Exec sessions are logged the way the task's own awslogs configuration logs, which here means they
  # land in the subscribed group and stream to Firehose along with the container's output.
  configuration {
    execute_command_configuration {
      logging = var.execute_command_logging
    }
  }
}
# The two Fargate providers the _monolithic template attached. The service places with launch_type FARGATE
# rather than through a strategy, so neither is used by it - they are here so a task run by hand can choose
# FARGATE_SPOT.
resource "aws_ecs_cluster_capacity_providers" "ecs_cluster" {
  cluster_name       = aws_ecs_cluster.ecs_cluster.name
  capacity_providers = var.capacity_providers
}
