# A Cloud Map private DNS namespace and the one service in it that the nginx tasks register under.
#
# The namespace is a Route 53 private hosted zone associated with the VPC, so any resolver in the VPC answers
# for it - the dnsutils task included, with no proxy and no configuration of its own. That is the contrast with
# 085_ecs_service_connect, and the reason this project needs no Service Connect anywhere.
resource "aws_service_discovery_private_dns_namespace" "service_discovery_namespace" {
  name        = var.namespace_name
  vpc         = var.vpc_id
  description = var.namespace_description
}
resource "aws_service_discovery_service" "service_discovery_service" {
  name = var.service_name
  dns_config {
    namespace_id = aws_service_discovery_private_dns_namespace.service_discovery_namespace.id
    # One A record per task, each task's ENI address - awsvpc gives every task its own, which is what makes
    # A records possible at all. A bridge-mode task would need SRV records carrying the host port instead.
    dns_records {
      type = var.dns_record_type
      ttl  = var.dns_ttl
    }
    # MULTIVALUE, as the _monolithic template had it: a query returns up to eight healthy records, so the
    # client spreads across the tasks itself. WEIGHTED would return one at random per query.
    routing_policy = var.routing_policy
  }
  # Health is whatever ECS reports, not a Route 53 health check - Route 53 cannot reach private addresses.
  # ECS marks an instance unhealthy when its task stops being healthy and Cloud Map then drops it from answers.
  #
  # Empty, where the _monolithic template wrote failure_threshold = 1. The argument is deprecated in the
  # provider because Cloud Map ignores it and always uses 1, so the template's value was the only value.
  health_check_custom_config {}
  # The ECS service owns the instances: it registers each task and deregisters it when the task stops. On
  # destroy that deregistration races this resource, which Cloud Map refuses to delete with
  # ResourceInUse while an instance is still registered. force_destroy deregisters what is left first.
  force_destroy = true
}
