# The Cloud Map namespace Service Connect publishes endpoints in.
#
# An HTTP namespace, as the _monolithic template had it: Service Connect does not need DNS records - the
# proxy in each client task resolves the client aliases itself and ECS writes them into the task's
# /etc/hosts - so a namespace that only holds instances for API discovery is enough, and unlike a private DNS
# namespace it creates no hosted zone and is not tied to a VPC.
#
# Nothing here registers instances. ECS creates the Cloud Map service for each Service Connect endpoint when
# the ECS service that publishes it is created, and registers and deregisters the tasks itself.
resource "aws_service_discovery_http_namespace" "service_connect_namespace" {
  name        = var.name
  description = var.description
}
