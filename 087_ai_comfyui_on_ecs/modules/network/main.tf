# The blueprint's VpcConstruct: a VPC over two zones with a public and a private /24 in each, NAT instances
# rather than NAT gateways, an S3 gateway endpoint, a flow log, and a default security group with no rules.
#
# The only data source here is the NAT instance AMI. This module is the one every other module waits for, so
# nothing defers it to apply (rules.md D-6).
data "aws_ssm_parameter" "nat_instance_ami" {
  name = var.nat_instance_ami_parameter
}
locals {
  # Two zones, as the blueprint's max_azs=2. The zone count follows what the project runs (rules.md C-3): an
  # internet-facing ALB, which AWS refuses to create in fewer than two zones, and one GPU instance, which only
  # needs a second zone to have somewhere to go when the first has no spot capacity.
  zones = {
    for index, suffix in var.availability_zone_suffixes : suffix => {
      index = index
      name  = "${var.region}${suffix}"
    }
  }
  # The addresses CDK allocated: every public /24 first, then every private /24, zone by zone - 10.0.0.0/24
  # and 10.0.1.0/24 public, 10.0.2.0/24 and 10.0.3.0/24 private for the default VPC block.
  subnet_newbits = 24 - tonumber(split("/", var.vpc_cidr_block)[1])
  public_cidr_blocks = {
    for suffix, zone in local.zones : suffix => cidrsubnet(var.vpc_cidr_block, local.subnet_newbits, zone.index)
  }
  private_cidr_blocks = {
    for suffix, zone in local.zones : suffix => cidrsubnet(var.vpc_cidr_block, local.subnet_newbits, length(local.zones) + zone.index)
  }
}
resource "aws_vpc" "vpc" {
  cidr_block           = var.vpc_cidr_block
  enable_dns_support   = true
  enable_dns_hostnames = true
  tags = {
    Name = var.name
  }
}
# The blueprint's @aws-cdk/aws-ec2:restrictDefaultSecurityGroup feature flag, which CDK implements as a custom
# resource Lambda that revokes the default group's rules after the VPC is created. Declaring the default group
# with no rule blocks does the same thing without the Lambda: Terraform removes every rule from it on create.
# Nothing here is placed in it.
resource "aws_default_security_group" "default" {
  vpc_id = aws_vpc.vpc.id
  tags = {
    Name = "${var.name}-default"
  }
}
resource "aws_internet_gateway" "internet_gateway" {
  vpc_id = aws_vpc.vpc.id
  tags = {
    Name = var.name
  }
}

# --- Public subnets: the load balancer and the NAT instances ---------------------------------------------

# for_each over the zone letters, which come from a variable and are known at plan, so they are safe resource
# addresses even though everything they create is not (rules.md B-8).
resource "aws_subnet" "public" {
  for_each                = local.zones
  vpc_id                  = aws_vpc.vpc.id
  availability_zone       = each.value.name
  cidr_block              = local.public_cidr_blocks[each.key]
  map_public_ip_on_launch = true
  tags = {
    Name = "${var.name}-public-${each.key}"
  }
}
# One route table per subnet, as CDK creates them, so the S3 endpoint below is associated with the same set
# of tables the blueprint's was.
resource "aws_route_table" "public" {
  for_each = local.zones
  vpc_id   = aws_vpc.vpc.id
  tags = {
    Name = "${var.name}-public-${each.key}"
  }
}
resource "aws_route" "public_internet" {
  for_each               = local.zones
  route_table_id         = aws_route_table.public[each.key].id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = aws_internet_gateway.internet_gateway.id
}
resource "aws_route_table_association" "public" {
  for_each       = local.zones
  route_table_id = aws_route_table.public[each.key].id
  subnet_id      = aws_subnet.public[each.key].id
}

# --- NAT instances --------------------------------------------------------------------------------------

# The blueprint's cheap_vpc=True, its default: NatProvider.instance_v2 with a t4g.nano in each public subnet
# instead of a NAT gateway, at a fraction of the hourly price and with the throughput and availability of one
# small instance. cheap_vpc=False (NAT gateways) is not converted - see main.tf at the root.
resource "aws_security_group" "nat" {
  name        = var.nat_security_group_name
  description = var.nat_security_group_description
  vpc_id      = aws_vpc.vpc.id
  tags = {
    Name = var.nat_security_group_name
  }
}
# Standalone rules rather than inline blocks (rules.md F-2). The ingress rule is the one the blueprint added
# to the NAT group itself: everything from inside the VPC, which is what the instances forward.
resource "aws_vpc_security_group_ingress_rule" "nat_from_vpc" {
  security_group_id = aws_security_group.nat.id
  description       = "Allow NAT traffic from inside the VPC"
  ip_protocol       = "-1"
  cidr_ipv4         = aws_vpc.vpc.cidr_block
}
resource "aws_vpc_security_group_egress_rule" "nat_all" {
  security_group_id = aws_security_group.nat.id
  description       = "All outbound"
  ip_protocol       = "-1"
  cidr_ipv4         = "0.0.0.0/0"
}
locals {
  # CDK's NatInstanceProviderV2 default user data - iptables masquerading out of the default route's interface,
  # and forwarding on - with a swap file in front of it.
  #
  # The swap file is the one addition, and without it these instances route nothing. A t4g.nano has 512 MiB,
  # and dnf resolving the Amazon Linux 2023 repositories needs more: the kernel's OOM killer stops yum about
  # 25 seconds after boot ("Out of memory: Killed process (yum)" in the console output), iptables-services is
  # never installed, the MASQUERADE rule is never added, and the instance forwards packets with private source
  # addresses that the internet gateway drops. Nothing reports that. The GPU instance then cannot reach ECS to
  # register, and ComfyUI never starts. The swap is only needed for the install; it is not kept across reboots.
  nat_instance_user_data = <<-EOT
    #!/bin/bash
    dd if=/dev/zero of=/swapfile bs=1M count=1024
    chmod 600 /swapfile
    mkswap /swapfile
    swapon /swapfile
    yum install iptables-services -y
    systemctl enable iptables
    systemctl start iptables
    echo "net.ipv4.ip_forward=1" > /etc/sysctl.d/custom-ip-forwarding.conf
    sudo sysctl -p /etc/sysctl.d/custom-ip-forwarding.conf
    sudo /sbin/iptables -t nat -A POSTROUTING -o $(route | awk '/^default/{print $NF}') -j MASQUERADE
    sudo /sbin/iptables -F FORWARD
    sudo service iptables save
    EOT
}
# No instance profile, where CDK gave each NAT instance a role with no policies attached. An empty role grants
# nothing, so leaving it out changes nothing the instance can do.
resource "aws_instance" "nat" {
  for_each               = local.zones
  ami                    = data.aws_ssm_parameter.nat_instance_ami.insecure_value
  instance_type          = var.nat_instance_type
  subnet_id              = aws_subnet.public[each.key].id
  vpc_security_group_ids = [aws_security_group.nat.id]
  # What makes an instance a router: without this EC2 drops every packet not addressed to the instance itself.
  source_dest_check = false
  user_data         = local.nat_instance_user_data
  # User data runs once, at first boot, so a changed script only takes effect on a new instance.
  user_data_replace_on_change = true

  # IMDSv2 only. The user data never reads the instance metadata, and Amazon Linux 2023 requires tokens by
  # default anyway - stated so the choice is visible.
  metadata_options {
    http_endpoint = "enabled"
    http_tokens   = "required"
  }

  tags = {
    Name = "${var.name}-nat-${each.key}"
  }

  lifecycle {
    # The AMI parameter moves with every Amazon Linux 2023 release, every couple of weeks. CloudFormation
    # replaced the instances on the next deploy after one; here that would be any apply at all, including one
    # that changes a WAF address range, and it cuts the GPU instance's outbound path while the replacement
    # boots. Replace them deliberately instead: terraform apply -replace='module.network.aws_instance.nat["a"]'.
    ignore_changes = [ami]
  }

  # The user data installs a package at first boot, so the instance needs its route out before it starts.
  # Nothing in this resource references the route or the egress rule (rules.md D-1).
  depends_on = [aws_route.public_internet, aws_vpc_security_group_egress_rule.nat_all]
}

# --- Private subnets: the GPU instance and its ECS task -------------------------------------------------

resource "aws_subnet" "private" {
  for_each          = local.zones
  vpc_id            = aws_vpc.vpc.id
  availability_zone = each.value.name
  cidr_block        = local.private_cidr_blocks[each.key]
  tags = {
    Name = "${var.name}-private-${each.key}"
  }
}
resource "aws_route_table" "private" {
  for_each = local.zones
  vpc_id   = aws_vpc.vpc.id
  tags = {
    Name = "${var.name}-private-${each.key}"
  }
}
# Through the zone's own NAT instance, as CDK routes each private subnet. Its network interface rather than
# the instance ID, which is the only target aws_route still accepts for an instance.
resource "aws_route" "private_nat" {
  for_each               = local.zones
  route_table_id         = aws_route_table.private[each.key].id
  destination_cidr_block = "0.0.0.0/0"
  network_interface_id   = aws_instance.nat[each.key].primary_network_interface_id
}
resource "aws_route_table_association" "private" {
  for_each       = local.zones
  route_table_id = aws_route_table.private[each.key].id
  subnet_id      = aws_subnet.private[each.key].id
}

# --- Endpoint and flow log ------------------------------------------------------------------------------

# The blueprint's gateway endpoint, which its comment explains: ECR serves image layers from S3, so the
# ComfyUI image - several gigabytes - is pulled without going through the NAT instance. On every route table,
# as CDK associates it.
resource "aws_vpc_endpoint" "s3" {
  vpc_id            = aws_vpc.vpc.id
  service_name      = "com.amazonaws.${var.region}.s3"
  vpc_endpoint_type = "Gateway"
  route_table_ids = concat(
    [for suffix in var.availability_zone_suffixes : aws_route_table.private[suffix].id],
    [for suffix in var.availability_zone_suffixes : aws_route_table.public[suffix].id],
  )
  tags = {
    Name = "${var.name}-s3"
  }
}
# The blueprint's FlowLog, every accepted and rejected packet in the VPC to CloudWatch Logs. The log group is
# declared rather than left to CDK's, which carried a Retain deletion policy and so outlived the stack; this
# one goes with terraform destroy.
resource "aws_cloudwatch_log_group" "flow_log" {
  name              = "/aws/vpc/flow-logs/${var.name}"
  retention_in_days = var.flow_log_retention_days
}
resource "aws_iam_role" "flow_log" {
  name_prefix = "${substr(var.name, 0, 28)}-flowlog-"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "vpc-flow-logs.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}
# The actions CDK granted, on the one log group. CDK also let the role pass itself, which the flow log
# service never does; it is the caller creating the flow log that needs iam:PassRole, so that statement is
# dropped.
resource "aws_iam_role_policy" "flow_log" {
  name = "flow-log"
  role = aws_iam_role.flow_log.name
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = ["logs:CreateLogStream", "logs:DescribeLogStreams", "logs:PutLogEvents"]
      Resource = ["${aws_cloudwatch_log_group.flow_log.arn}:*"]
    }]
  })
}
resource "aws_flow_log" "vpc" {
  vpc_id               = aws_vpc.vpc.id
  traffic_type         = "ALL"
  log_destination_type = "cloud-watch-logs"
  log_destination      = aws_cloudwatch_log_group.flow_log.arn
  iam_role_arn         = aws_iam_role.flow_log.arn
  tags = {
    Name = var.name
  }

  # The service checks it can write with the role when the flow log is created, and iam_role_arn does not
  # imply the inline policy (rules.md D-1).
  depends_on = [aws_iam_role_policy.flow_log]
}
