# Both VPCs, the peering connection between them and every route on both sides, in one module.
#
# That is unusual for this repository - 109_eks_cross_vpc_tgw gives each VPC its own module
# instance and hoists the transit gateway into the root (rules.md C-1) - and the reason it cannot
# be done here is the resource itself. A transit gateway exists before any attachment, so a
# network module can take its ID as an input. aws_vpc_peering_connection cannot: it names both
# VPC IDs at creation, while the routes inside both VPCs name the connection ID. Split per VPC,
# that is a cycle Terraform refuses.
#
# The alternative - two network modules plus a third that owns the connection and every route -
# means exporting eight route table IDs and declaring twelve routes in the root, each keyed by a
# static label because a route table ID is another module's output (rules.md B-8). One module
# that owns both sides is less machinery for the same graph.
#
# The _monolithic template named them vpc_a and vpc_b while tagging them ws25-hub-vpc and
# ws25-app-vpc. The tags say what they are, so the names here follow the tags: hub is vpc_a
# (public only, internet-facing entry point), app is vpc_b (public, private and internal tiers,
# everything that actually runs).
locals {
  hub_public_subnets = {
    for suffix, cidr_block in var.hub_public_subnet_cidr_blocks : suffix => {
      availability_zone = "${var.region}${suffix}"
      cidr_block        = cidr_block
    }
  }
  app_public_subnets = {
    for suffix, cidr_block in var.app_public_subnet_cidr_blocks : suffix => {
      availability_zone = "${var.region}${suffix}"
      cidr_block        = cidr_block
    }
  }
  app_private_subnets = {
    for suffix, cidr_block in var.app_private_subnet_cidr_blocks : suffix => {
      availability_zone = "${var.region}${suffix}"
      cidr_block        = cidr_block
    }
  }
  app_internal_subnets = {
    for suffix, cidr_block in var.app_internal_subnet_cidr_blocks : suffix => {
      availability_zone = "${var.region}${suffix}"
      cidr_block        = cidr_block
    }
  }
}
# --- Hub VPC (vpc_a): the internet-facing side. Two public subnets, no NAT, nothing private. ---
resource "aws_vpc" "hub" {
  cidr_block           = var.hub_vpc_cidr_block
  enable_dns_support   = true
  enable_dns_hostnames = true
  tags = {
    Name = var.hub_vpc_name
  }
}
# vpc_id on the gateway rather than the separate aws_internet_gateway_attachment the conversion
# produced. CloudFormation models the gateway and its attachment as two resources; the Terraform
# provider takes vpc_id here, and that also makes the route below ordered after the attachment
# instead of only after an unattached gateway - a route to a detached gateway is rejected with
# InvalidGatewayID.NotAttached.
resource "aws_internet_gateway" "hub" {
  vpc_id = aws_vpc.hub.id
  tags = {
    Name = var.hub_internet_gateway_name
  }
}
resource "aws_subnet" "hub_public" {
  for_each = local.hub_public_subnets

  vpc_id                  = aws_vpc.hub.id
  availability_zone       = each.value.availability_zone
  cidr_block              = each.value.cidr_block
  map_public_ip_on_launch = true
  tags = {
    Name = "${var.hub_public_subnet_name_prefix}-${each.key}"
  }
}
resource "aws_route_table" "hub_public" {
  vpc_id = aws_vpc.hub.id
  tags = {
    Name = var.hub_public_route_table_name
  }
}
resource "aws_route" "hub_public_internet" {
  route_table_id         = aws_route_table.hub_public.id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = aws_internet_gateway.hub.id
}
resource "aws_route_table_association" "hub_public" {
  for_each = aws_subnet.hub_public

  route_table_id = aws_route_table.hub_public.id
  subnet_id      = each.value.id
}
# --- App VPC (vpc_b): three tiers. ---
resource "aws_vpc" "app" {
  cidr_block           = var.app_vpc_cidr_block
  enable_dns_support   = true
  enable_dns_hostnames = true
  tags = {
    Name = var.app_vpc_name
  }
}
resource "aws_internet_gateway" "app" {
  vpc_id = aws_vpc.app.id
  tags = {
    Name = var.app_internet_gateway_name
  }
}
resource "aws_subnet" "app_public" {
  for_each = local.app_public_subnets

  vpc_id                  = aws_vpc.app.id
  availability_zone       = each.value.availability_zone
  cidr_block              = each.value.cidr_block
  map_public_ip_on_launch = true
  tags = {
    Name = "${var.app_public_subnet_name_prefix}-${each.key}"
  }
}
resource "aws_route_table" "app_public" {
  vpc_id = aws_vpc.app.id
  tags = {
    Name = var.app_public_route_table_name
  }
}
resource "aws_route" "app_public_internet" {
  route_table_id         = aws_route_table.app_public.id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = aws_internet_gateway.app.id
}
resource "aws_route_table_association" "app_public" {
  for_each = aws_subnet.app_public

  route_table_id = aws_route_table.app_public.id
  subnet_id      = each.value.id
}
# The private tier: the ECS container instances, the tasks, the internal ALB and the internal NLB.
resource "aws_subnet" "app_private" {
  for_each = local.app_private_subnets

  vpc_id            = aws_vpc.app.id
  availability_zone = each.value.availability_zone
  cidr_block        = each.value.cidr_block
  tags = {
    Name = "${var.app_private_subnet_name_prefix}-${each.key}"
  }
}
resource "aws_eip" "app_nat_gateway" {
  for_each = local.app_private_subnets

  # domain rather than the deprecated vpc = true. The _monolithic template declared a bare
  # aws_eip {} and relied on the provider default.
  domain = "vpc"
  tags = {
    Name = "${var.app_nat_gateway_name_prefix}-${each.key}"
  }
}
# A NAT gateway per zone, as the _monolithic template had it. Worth saying why that is not
# over-provisioning: the per-zone route table below sends each private subnet through the gateway
# in its own zone, so a shared gateway would push half the egress across a zone boundary - billed
# per gigabyte - and would take all three subnets offline when its zone failed.
resource "aws_nat_gateway" "app" {
  for_each = local.app_private_subnets

  allocation_id = aws_eip.app_nat_gateway[each.key].allocation_id
  # In the public subnet of the same zone. A NAT gateway placed in the subnet it serves routes
  # its own egress back to itself.
  subnet_id = aws_subnet.app_public[each.key].id
  tags = {
    Name = "${var.app_nat_gateway_name_prefix}-${each.key}"
  }

  depends_on = [aws_internet_gateway.app]
}
resource "aws_route_table" "app_private" {
  for_each = local.app_private_subnets

  vpc_id = aws_vpc.app.id
  tags = {
    Name = "${var.app_private_route_table_name_prefix}-${each.key}"
  }
}
resource "aws_route" "app_private_internet" {
  for_each = local.app_private_subnets

  route_table_id         = aws_route_table.app_private[each.key].id
  destination_cidr_block = "0.0.0.0/0"
  nat_gateway_id         = aws_nat_gateway.app[each.key].id
}
resource "aws_route_table_association" "app_private" {
  for_each = aws_subnet.app_private

  route_table_id = aws_route_table.app_private[each.key].id
  subnet_id      = each.value.id
}
# The internal tier: the Aurora subnet group, and nothing else.
#
# It has a route table per zone carrying only the peering route - no 0.0.0.0/0 at all, which is
# the point of the tier. The database has no path to the internet in either direction, and the S3
# and ECR endpoints below are attached to these tables so the AWS calls that do happen stay on
# the VPC.
resource "aws_subnet" "app_internal" {
  for_each = local.app_internal_subnets

  vpc_id            = aws_vpc.app.id
  availability_zone = each.value.availability_zone
  cidr_block        = each.value.cidr_block
  tags = {
    Name = "${var.app_internal_subnet_name_prefix}-${each.key}"
  }
}
resource "aws_route_table" "app_internal" {
  for_each = local.app_internal_subnets

  vpc_id = aws_vpc.app.id
  tags = {
    Name = "${var.app_internal_route_table_name_prefix}-${each.key}"
  }
}
resource "aws_route_table_association" "app_internal" {
  for_each = aws_subnet.app_internal

  route_table_id = aws_route_table.app_internal[each.key].id
  subnet_id      = each.value.id
}
# --- The peering connection and the routes that make it useful. ---
#
# auto_accept, which the _monolithic template did not set, and the project does not work without
# it.
#
# CloudFormation's AWS::EC2::VPCPeeringConnection accepts the request itself when both VPCs are
# in the same account, so the template never had to say so. Terraform does not: with auto_accept
# left at false the connection is created in pending-acceptance and apply reports success, and
# then every aws_route below fails with InvalidVpcPeeringConnectionState because a route cannot
# point at a connection that is not active. The error names the route, not the connection, so the
# obvious reading is that something is wrong with the route table.
resource "aws_vpc_peering_connection" "peering" {
  vpc_id      = aws_vpc.hub.id
  peer_vpc_id = aws_vpc.app.id
  auto_accept = true
  tags = {
    Name = var.peering_connection_name
  }
}
# One route per route table that needs to reach the other side. The hub has a single public table;
# the app side has one public table and one per private and internal subnet, so every table that
# exists gets a route - a peering connection with routes on only one side drops the reply, which
# looks like a timeout rather than a routing error.
resource "aws_route" "hub_public_peering" {
  route_table_id            = aws_route_table.hub_public.id
  destination_cidr_block    = aws_vpc.app.cidr_block
  vpc_peering_connection_id = aws_vpc_peering_connection.peering.id
}
resource "aws_route" "app_public_peering" {
  route_table_id            = aws_route_table.app_public.id
  destination_cidr_block    = aws_vpc.hub.cidr_block
  vpc_peering_connection_id = aws_vpc_peering_connection.peering.id
}
resource "aws_route" "app_private_peering" {
  for_each = local.app_private_subnets

  route_table_id            = aws_route_table.app_private[each.key].id
  destination_cidr_block    = aws_vpc.hub.cidr_block
  vpc_peering_connection_id = aws_vpc_peering_connection.peering.id
}
resource "aws_route" "app_internal_peering" {
  for_each = local.app_internal_subnets

  route_table_id            = aws_route_table.app_internal[each.key].id
  destination_cidr_block    = aws_vpc.hub.cidr_block
  vpc_peering_connection_id = aws_vpc_peering_connection.peering.id
}
# --- Flow logs. ---
#
# The log groups are Terraform resources here; the _monolithic template pointed each flow log at a
# log group ARN it never declared and let the CreateFlowLogs call bring it into existence. That
# works, and it leaves two log groups behind after destroy with no retention set, collecting ALL
# traffic from both VPCs forever. Declaring them puts them in state, gives them a retention and
# lets the dashboard reference the same names rather than restating them (rules.md B-5).
resource "aws_cloudwatch_log_group" "hub_flow_log" {
  name              = var.hub_flow_log_group_name
  retention_in_days = var.flow_log_retention_in_days
}
resource "aws_cloudwatch_log_group" "app_flow_log" {
  name              = var.app_flow_log_group_name
  retention_in_days = var.flow_log_retention_in_days
}
resource "aws_iam_role" "flow_log" {
  name_prefix = var.flow_log_role_name_prefix
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Action = ["sts:AssumeRole"]
      Principal = {
        Service = ["vpc-flow-logs.amazonaws.com"]
      }
    }]
  })
}
# One role for both VPCs rather than the template's two identical ones, and scoped to the two log
# groups rather than Resource "*" (rules.md A-5).
#
# This is the narrowing case the rule calls out as a judgement: the _monolithic template attached
# these permissions in Terraform, so tightening them changes what the original did. It wrote
# logs:CreateLogGroup, CreateLogStream, PutLogEvents, DescribeLogGroups and DescribeLogStreams
# against every log group in the account, for a role whose only job is to write into two of them.
#
# DescribeLogGroups stays on "*" because CloudWatch Logs has no resource-level permission for it -
# scoping it produces an AccessDenied that stops flow log delivery with no message anywhere except
# the flow log's own status field.
resource "aws_iam_role_policy" "flow_log" {
  name = "CloudWatchLogsPolicy"
  role = aws_iam_role.flow_log.name
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = ["logs:CreateLogStream", "logs:PutLogEvents", "logs:DescribeLogStreams"]
        Resource = [
          "${aws_cloudwatch_log_group.hub_flow_log.arn}:*",
          "${aws_cloudwatch_log_group.app_flow_log.arn}:*",
        ]
      },
      {
        Effect   = "Allow"
        Action   = ["logs:DescribeLogGroups"]
        Resource = "*"
      },
    ]
  })
}
resource "aws_flow_log" "hub" {
  iam_role_arn             = aws_iam_role.flow_log.arn
  log_destination_type     = "cloud-watch-logs"
  log_destination          = aws_cloudwatch_log_group.hub_flow_log.arn
  max_aggregation_interval = var.flow_log_max_aggregation_interval
  traffic_type             = "ALL"
  vpc_id                   = aws_vpc.hub.id
  tags = {
    Name = "${var.hub_vpc_name}-flow-log"
  }

  # The role has to carry its policy before delivery starts. Nothing in this resource refers to
  # the policy, and a missing one does not fail the create - the flow log is accepted and then
  # reports FAILED in its DeliverLogsStatus, which nothing surfaces (rules.md D-1).
  depends_on = [aws_iam_role_policy.flow_log]
}
resource "aws_flow_log" "app" {
  iam_role_arn             = aws_iam_role.flow_log.arn
  log_destination_type     = "cloud-watch-logs"
  log_destination          = aws_cloudwatch_log_group.app_flow_log.arn
  max_aggregation_interval = var.flow_log_max_aggregation_interval
  traffic_type             = "ALL"
  vpc_id                   = aws_vpc.app.id
  # The template tagged this one "vpc-a-flow-log" as well, so both flow logs carried the hub's
  # name and the console showed two identical rows.
  tags = {
    Name = "${var.app_vpc_name}-flow-log"
  }

  depends_on = [aws_iam_role_policy.flow_log]
}
# --- VPC endpoints, all three on the app side. ---
#
# These are what let the private and internal tiers work with a NAT gateway that may be saturated
# or, for the internal tier, no internet route at all. The gateway endpoint is attached to the
# private and internal route tables; the two interface endpoints sit in the private subnets.
resource "aws_vpc_endpoint" "app_s3" {
  vpc_id            = aws_vpc.app.id
  service_name      = "com.amazonaws.${var.region}.s3"
  vpc_endpoint_type = "Gateway"
  route_table_ids = concat(
    [for table in aws_route_table.app_private : table.id],
    [for table in aws_route_table.app_internal : table.id],
  )
  tags = {
    Name = "${var.app_vpc_name}-s3-endpoint"
  }
}
resource "aws_security_group" "app_ecr_endpoint" {
  name        = var.app_ecr_endpoint_security_group_name
  description = var.app_ecr_endpoint_security_group_description
  vpc_id      = aws_vpc.app.id
  tags = {
    Name = var.app_ecr_endpoint_security_group_name
  }
}
# Standalone rule resources rather than inline ingress/egress blocks (rules.md F-2), and here that
# is not a style preference - the _monolithic template's version of this group has no outbound
# access at all.
#
# The template declared nine aws_security_group resources carrying seventeen inline ingress blocks
# and not one egress block. CloudFormation's AWS::EC2::SecurityGroup leaves the allow-all egress
# rule that EC2 attaches to every new group alone when a template names only SecurityGroupIngress,
# so the source template never had to spell outbound out. Terraform's inline blocks are
# attributes-as-blocks and authoritative over the whole group: omitting egress does not inherit
# that default, it revokes it.
#
# Converted as written, that leaves every group in this project with zero outbound access while
# apply reports complete success. For this group specifically it is self-defeating - an interface
# endpoint's own ENI needs to answer, and the group guarding it is the first hop - and the same
# bug broke 101_ubuntu_xrdp outright and was found twice in 103_ecs_volumes. Every group in this
# project now has an explicit egress rule for that reason.
resource "aws_vpc_security_group_ingress_rule" "app_ecr_endpoint" {
  security_group_id = aws_security_group.app_ecr_endpoint.id
  description       = "HTTPS from inside the app VPC"
  ip_protocol       = "tcp"
  from_port         = var.https_port
  to_port           = var.https_port
  cidr_ipv4         = var.app_vpc_cidr_block
}
resource "aws_vpc_security_group_egress_rule" "app_ecr_endpoint" {
  security_group_id = aws_security_group.app_ecr_endpoint.id
  description       = "All outbound"
  ip_protocol       = "-1"
  cidr_ipv4         = "0.0.0.0/0"
}
# One security group for both ECR endpoints rather than the template's two identical ones. They
# guard the same traffic from the same source on the same port; two groups meant two places to
# change and no way to tell them apart in a console listing.
resource "aws_vpc_endpoint" "app_ecr_dkr" {
  vpc_id              = aws_vpc.app.id
  service_name        = "com.amazonaws.${var.region}.ecr.dkr"
  vpc_endpoint_type   = "Interface"
  subnet_ids          = [for subnet in aws_subnet.app_private : subnet.id]
  security_group_ids  = [aws_security_group.app_ecr_endpoint.id]
  private_dns_enabled = true
  tags = {
    Name = "${var.app_vpc_name}-ecr-dkr-endpoint"
  }
}
# Both ECR endpoints are needed, not either one: ecr.api serves the authorization token and the
# repository metadata, ecr.dkr serves the layers. With only one of them a pull fails halfway, and
# the task's stopped reason names a timeout rather than a missing endpoint.
resource "aws_vpc_endpoint" "app_ecr_api" {
  vpc_id              = aws_vpc.app.id
  service_name        = "com.amazonaws.${var.region}.ecr.api"
  vpc_endpoint_type   = "Interface"
  subnet_ids          = [for subnet in aws_subnet.app_private : subnet.id]
  security_group_ids  = [aws_security_group.app_ecr_endpoint.id]
  private_dns_enabled = true
  tags = {
    Name = "${var.app_vpc_name}-ecr-api-endpoint"
  }
}
