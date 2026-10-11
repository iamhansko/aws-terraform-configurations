# The cluster only. The managed instances capacity provider is cluster-scoped and names this cluster itself,
# so there is no aws_ecs_cluster_capacity_providers association to declare - the _monolithic template had
# none either.
resource "aws_ecs_cluster" "ecs_cluster" {
  # CloudFormation generated this name; Terraform requires one, so the caller derives it from the project
  # name as the _monolithic template did from the stack name.
  name = var.name
  setting {
    name  = "containerInsights"
    value = var.container_insights
  }
}
