data "aws_region" "current" {}
# The client-VPC half: one endpoint onto the service network, and the DNS that makes the cluster's own hostname
# resolve to it.
#
# ---------------------------------------------------------------------------------------------------
# Where the Lambda went
# ---------------------------------------------------------------------------------------------------
#
# The _monolithic template needed the endpoint's DNS name and hosted zone id to build the alias record below,
# and there was no Terraform attribute for them - a ServiceNetwork endpoint publishes its DNS per association
# rather than on the endpoint itself. So it shipped a CloudFormation custom resource: a Lambda with
# AmazonEC2FullAccess that called describe_vpc_endpoint_associations and returned the two values.
#
# That Lambda could not have run, for three separate reasons:
#
#   - the file the archive was built from contained a Python dict repr of the CloudFormation Fn::Sub object
#     that was supposed to produce the code, so it was not valid Python at all
#   - the code imported cfnresponse, which CloudFormation provides only to inline Lambda code
#   - it read its arguments from event["ResourceProperties"], which is not the shape aws_lambda_invocation sends
#
# data.aws_vpc_endpoint_associations returns exactly those two fields, so the Lambda, its role, its
# AmazonEC2FullAccess attachment, its archive_file and the aws_lambda_invocation all go (rules.md A-5) - the
# same substitution 070_eks_vpc_lattice makes for its own cfnresponse Lambda.
# ---------------------------------------------------------------------------------------------------
resource "aws_security_group" "endpoint" {
  name        = "${var.name_prefix}-lattice-endpoint-sg"
  description = "Attached to the VPC Lattice service network endpoint that reaches the EKS API server"
  vpc_id      = var.vpc_id

  tags = {
    Name = "${var.name_prefix}-lattice-endpoint-sg"
  }
}
# Standalone rules rather than the inline ingress block the _monolithic template used (rules.md F-2).
resource "aws_vpc_security_group_ingress_rule" "endpoint_from_vpc" {
  security_group_id = aws_security_group.endpoint.id
  description       = "HTTPS from anything in the client VPC"
  ip_protocol       = "tcp"
  from_port         = 443
  to_port           = 443
  cidr_ipv4         = var.vpc_cidr_block
}
resource "aws_vpc_security_group_ingress_rule" "endpoint_from_extra_cidrs" {
  for_each = toset(var.allowed_ingress_cidr_blocks)

  security_group_id = aws_security_group.endpoint.id
  description       = "HTTPS from ${each.value}"
  ip_protocol       = "tcp"
  from_port         = 443
  to_port           = 443
  cidr_ipv4         = each.value
}
resource "aws_vpc_endpoint" "service_network" {
  vpc_endpoint_type = "ServiceNetwork"
  vpc_id            = var.vpc_id
  # The ARN, not the id. The provider's service_network_arn argument takes an ARN and the _monolithic template
  # passed the service network's id into it - which the conversion produced because CloudFormation's Ref
  # returns one value for both.
  service_network_arn = var.service_network_arn
  subnet_ids          = var.subnet_ids
  security_group_ids  = [aws_security_group.endpoint.id]

  tags = {
    Name = "${var.name_prefix}-lattice-endpoint"
  }
}
# The DNS name and hosted zone the endpoint's association publishes - what the deleted Lambda existed to fetch.
#
# Read at apply time rather than during plan, which is unavoidable: the association does not exist until the
# endpoint does. That is fine here because the values are used as attributes of the record below rather than as
# a for_each key, which is the case where a deferred data source causes trouble (rules.md D-6).
data "aws_vpc_endpoint_associations" "service_network" {
  count = var.create_private_hosted_zone ? 1 : 0

  vpc_endpoint_id = aws_vpc_endpoint.service_network.id
}
# A private hosted zone for the cluster's own API server hostname, resolvable only inside the client VPC.
#
# This is the trick that makes the whole thing usable: the client resolves the real endpoint name, so the
# certificate the API server presents matches and a kubeconfig written by aws eks update-kubeconfig needs no
# editing. Without it a client would have to target the endpoint's own DNS name, and TLS verification would
# fail on the name mismatch.
resource "aws_route53_zone" "api_server" {
  count = var.create_private_hosted_zone ? 1 : 0

  name    = var.api_server_hostname
  comment = "Resolves the EKS API server hostname to the VPC Lattice endpoint inside the client VPC"

  vpc {
    vpc_id     = var.vpc_id
    vpc_region = data.aws_region.current.region
  }

  tags = {
    Name = "${var.name_prefix}-api-server-zone"
  }
}
resource "aws_route53_record" "api_server" {
  count = var.create_private_hosted_zone ? 1 : 0

  zone_id = aws_route53_zone.api_server[0].zone_id
  name    = var.api_server_hostname
  type    = "A"

  alias {
    # The first association's DNS entry. There is one association per service network attached to the endpoint,
    # and this endpoint attaches to exactly one.
    name    = data.aws_vpc_endpoint_associations.service_network[0].associations[0].dns_entry[0].dns_name
    zone_id = data.aws_vpc_endpoint_associations.service_network[0].associations[0].dns_entry[0].hosted_zone_id
    # False, as the _monolithic template had it. Health evaluation on a Lattice endpoint alias would need the
    # target to publish health, which it does not.
    evaluate_target_health = false
  }
}
