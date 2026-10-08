# The cluster-VPC half of reaching a private EKS API server from another VPC through VPC Lattice.
#
# Four resources that are one mechanism, which is why they are one module (rules.md C-2):
#
#   resource gateway        - interfaces in the cluster's private subnets. This is what actually resolves and
#                             connects to the API server's private endpoint, so it has to live in the VPC where
#                             that endpoint is reachable.
#   resource configuration  - names the target: the API server's hostname, on port 443. It is the unit a
#                             service network can be given.
#   service network         - the thing a client VPC attaches an endpoint to.
#   association             - joins the configuration to the network, with private DNS on.
#
# None of the four is useful without the others, and three of them carry the API server's hostname - so
# splitting them would mean restating it.
#
# What this replaces: a peering connection or a transit gateway plus a Route 53 resolver rule and inbound
# endpoints, which is the older way to reach a private API server across VPCs. Lattice does it without routing
# the two VPCs to each other at all - the client VPC gets one endpoint and no route to the cluster's network.
resource "aws_security_group" "resource_gateway" {
  name        = "${var.name_prefix}-resource-gateway-sg"
  description = "Attached to the VPC Lattice resource gateway that reaches the EKS API server private endpoint"
  vpc_id      = var.vpc_id

  tags = {
    Name = "${var.name_prefix}-resource-gateway-sg"
  }
}
# Standalone rule resources rather than inline blocks (rules.md F-2). The gateway needs egress to the API
# server; the _monolithic template declared this group with no rules at all and relied on the provider's
# default egress, which is allow-all - so the behaviour was right and invisible.
resource "aws_vpc_security_group_egress_rule" "resource_gateway_to_api_server" {
  security_group_id = aws_security_group.resource_gateway.id
  # No apostrophe: EC2 rejects a rule description outside a-zA-Z0-9. _-:/()#,@[]+=&;{}!$* and an apostrophe is
  # the character English prose puts there by itself. The call fails with InvalidParameterValue partway through
  # the apply, since neither validate nor plan looks at the value - and literals like this one are not covered
  # by any variable validation (rules.md F-1).
  description                  = "HTTPS to the API server endpoint of the cluster"
  ip_protocol                  = "tcp"
  from_port                    = 443
  to_port                      = 443
  referenced_security_group_id = var.cluster_security_group_id
}
# The other side of that hop, on a group this module does not own - so the caller supplies the ID and the rule
# lives here, next to the group it is about (rules.md B-6).
#
# Without it the gateway resolves the endpoint and every connection through it times out, which looks like a
# Lattice problem rather than a security group one.
resource "aws_vpc_security_group_ingress_rule" "api_server_from_resource_gateway" {
  security_group_id            = var.cluster_security_group_id
  description                  = "HTTPS from the VPC Lattice resource gateway"
  ip_protocol                  = "tcp"
  from_port                    = 443
  to_port                      = 443
  referenced_security_group_id = aws_security_group.resource_gateway.id
}
resource "aws_vpclattice_resource_gateway" "gateway" {
  name               = "${var.name_prefix}-resource-gateway"
  vpc_id             = var.vpc_id
  subnet_ids         = var.subnet_ids
  security_group_ids = [aws_security_group.resource_gateway.id]
  ip_address_type    = var.ip_address_type

  tags = {
    Name = "${var.name_prefix}-resource-gateway"
  }
}
resource "aws_vpclattice_resource_configuration" "api_server" {
  name                        = "${var.name_prefix}-api-server"
  resource_gateway_identifier = aws_vpclattice_resource_gateway.gateway.id
  # SINGLE: one resource behind one gateway, identified by a DNS name. The alternatives are ARN for an AWS
  # resource and GROUP for a set of them.
  type        = "SINGLE"
  protocol    = "TCP"
  port_ranges = var.port_ranges
  # This property came through the CloudFormation conversion as a commented-out TODO, so it was lost. It cannot
  # be changed after creation, which makes silently defaulting it the worse kind of loss.
  allow_association_to_shareable_service_network = var.allow_association_to_shareable_service_network
  # The name clients resolve. Setting it to the API server's own hostname is what lets a kubeconfig produced by
  # aws eks update-kubeconfig work unchanged from the client VPC - the certificate matches because the name is
  # the real one.
  custom_domain_name = var.api_server_hostname

  resource_configuration_definition {
    dns_resource {
      domain_name     = var.api_server_hostname
      ip_address_type = var.ip_address_type
    }
  }

  tags = {
    Name = "${var.name_prefix}-api-server"
  }
}
resource "aws_vpclattice_service_network" "service_network" {
  name = "${var.name_prefix}-service-network"

  tags = {
    Name = "${var.name_prefix}-service-network"
  }
}
resource "aws_vpclattice_service_network_resource_association" "api_server" {
  resource_configuration_identifier = aws_vpclattice_resource_configuration.api_server.id
  service_network_identifier        = aws_vpclattice_service_network.service_network.id

  tags = {
    Name = "${var.name_prefix}-api-server-association"
  }
}
