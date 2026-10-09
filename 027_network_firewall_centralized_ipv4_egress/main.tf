data "aws_region" "current" {}
# The AMI id for the workbench, from the public parameter AWS maintains for the latest Amazon Linux 2023.
#
# insecure_value rather than value: the provider marks a parameter's value sensitive whatever its type, and
# a sensitive value cannot be used as an instance's ami attribute without nonsensitive(). insecure_value is
# the provider's own accessor for a parameter that is not a secret, and a public AMI id is not one. This is
# what the _monolithic file did too.
#
# Declared here and passed into the module as a resolved id, so the module takes an ami- id and does not
# have to know where it came from (rules.md B-6). It also keeps the lookup out of a module that carries
# depends_on, which would defer the read to apply (rules.md D-6) - harmless for an AMI id, which feeds no
# for_each key, but there is no reason to take it on.
data "aws_ssm_parameter" "al2023_ami_id" {
  name = var.al2023_ami_ssm_parameter_name
}
locals {
  # The two zone names, built once and handed to both VPC modules.
  #
  # This is not tidiness. With appliance mode off, a transit gateway keeps a flow in the zone it arrived in
  # whenever the destination attachment has a subnet in that zone - so traffic from the spoke's zone a
  # lands in the egress VPC's zone a, hits that zone's attachment route table, that zone's firewall
  # endpoint and that zone's NAT gateway. The whole per-zone layout below only holds together if "zone a"
  # means the same zone in both VPCs, and building the pair here makes that true by construction rather
  # than by both modules happening to be given the same input.
  #
  # data.aws_region is read in the root rather than inside the VPC modules for the same reason the AMI
  # lookup is: a data source inside a module that carries depends_on is deferred to apply (rules.md D-6),
  # and these two strings are also what the modules' availability zone validations are checked against.
  availability_zone_a = "${data.aws_region.current.region}${var.availability_zone_a_suffix}"
  availability_zone_b = "${data.aws_region.current.region}${var.availability_zone_b_suffix}"
}
# How rules.md D-3 is satisfied in a root with two VPC modules rather than one "network"
# --------------------------------------------------------------------------------------
# D-3 says every module in a root that has a network module starts only after that module has finished, so
# that no reader has to decide per module whether an omission was reasoned or forgotten. This root has two
# VPCs, egress_vpc and app_vpc, and neither is "the" network module.
#
# The intent is kept by making every other module reachable from *both* of them through depends_on edges,
# directly or through another module - a module-level depends_on means "after every resource in that
# module", so the relation composes. The edges are:
#
#   egress_vpc, app_vpc          no depends_on; they are the two roots of the forest
#   transit_gateway              -> egress_vpc, app_vpc
#   network_firewall             -> egress_vpc, app_vpc
#   key_pair                     -> egress_vpc, app_vpc
#   vscode_ec2                   -> app_vpc, egress_vpc, network_firewall, key_pair, and the root's
#                                  attachments and routes
#
# So the reachable set from either VPC module is every other module, and there is no exception to look at
# twice. Value references do not count towards this: subnet_ids = module.egress_vpc.peering_subnet_ids
# orders a resource after those two subnets and after nothing else in that module - not after the internet
# gateway attachment, not after the NAT gateways - which is exactly the gap D-3 exists to close.
module "egress_vpc" {
  source = "./modules/egress_vpc"

  vpc_cidr_block      = var.egress_vpc_cidr_block
  vpc_name            = var.egress_vpc_name
  availability_zone_a = local.availability_zone_a
  availability_zone_b = local.availability_zone_b

  internet_gateway_name            = var.egress_internet_gateway_name
  public_subnet_name_prefix        = var.egress_public_subnet_name_prefix
  peering_subnet_name_prefix       = var.egress_peering_subnet_name_prefix
  firewall_subnet_name_prefix      = var.egress_firewall_subnet_name_prefix
  public_route_table_name          = var.egress_public_route_table_name
  peering_route_table_name_prefix  = var.egress_peering_route_table_name_prefix
  firewall_route_table_name_prefix = var.egress_firewall_route_table_name_prefix
  nat_gateway_name_prefix          = var.egress_nat_gateway_name_prefix
}
module "app_vpc" {
  source = "./modules/app_vpc"

  vpc_cidr_block      = var.app_vpc_cidr_block
  vpc_name            = var.app_vpc_name
  availability_zone_a = local.availability_zone_a
  availability_zone_b = local.availability_zone_b

  private_subnet_name_prefix = var.app_private_subnet_name_prefix
  route_table_name           = var.app_route_table_name
}
module "transit_gateway" {
  source = "./modules/transit_gateway"

  name = var.transit_gateway_name

  # Both VPCs, because the two attachments declared below follow this module immediately and each needs a
  # VPC that is already complete. It is also what makes destroy run in the right order: the attachments go
  # before the gateway, and the gateway before the VPCs whose subnets held its network interfaces
  # (rules.md D-2/D-3).
  depends_on = [module.egress_vpc, module.app_vpc]
}
module "network_firewall" {
  source = "./modules/network_firewall"

  vpc_id = module.egress_vpc.vpc_id
  # The two dedicated firewall subnets, named individually rather than passed as a list, so the endpoint
  # ids this module hands back can be matched to the zone the caller meant. A list would make the pairing
  # positional, and the one mistake in this area that produces no error at all is a route pointing at the
  # other zone's endpoint (rules.md B-6).
  firewall_subnet_a_id = module.egress_vpc.firewall_subnet_a_id
  firewall_subnet_b_id = module.egress_vpc.firewall_subnet_b_id

  firewall_name        = var.firewall_name
  firewall_policy_name = var.firewall_policy_name
  delete_protection    = var.firewall_delete_protection
  log_types            = var.firewall_log_types
  log_retention_days   = var.firewall_log_retention_days

  # egress_vpc is a real dependency beyond the two subnet references: a firewall endpoint is created in a
  # subnet, and the endpoint is only useful once that zone's route tables exist. app_vpc is listed so that
  # every module in this root is behind both VPC modules without exception (rules.md D-3).
  depends_on = [module.egress_vpc, module.app_vpc]
}
# --- The transit gateway attachments and the routes that reach across module boundaries ---
#
# These five resources live in the root rather than in any module, and the reason is the same for all of
# them: each one needs values from two modules that know nothing about each other, and joining two modules'
# outputs is the root's job (rules.md C-1).
#
#   - an attachment needs the gateway and a VPC with its subnets
#   - the two VPC routes that target the gateway need the gateway and a route table a VPC module owns
#   - the two attachment-subnet routes need a firewall endpoint and a route table, and the firewall is
#     created inside the subnets the egress VPC module owns, so a route in that module would close a cycle
#
# They are also where a wrong value is most expensive, because a wrong route is not an error. Every one of
# them is commented with what it carries and what breaks without it.
resource "aws_ec2_transit_gateway_vpc_attachment" "egress_vpc_tgw_attachment" {
  transit_gateway_id = module.transit_gateway.transit_gateway_id
  vpc_id             = module.egress_vpc.vpc_id
  # The attachment subnets, one per zone. These are the subnets the gateway puts its network interfaces in,
  # and they are what makes the gateway available in each zone - which in turn is what lets it keep a flow
  # in the zone it arrived in. A single subnet here would funnel both zones' traffic through one zone.
  subnet_ids = module.egress_vpc.peering_subnet_ids

  # Disabled, as the _monolithic template left it. The firewall is ahead of the NAT gateway and the return
  # traffic is addressed to the NAT gateway's Elastic IP, so nothing needs to be steered back through the
  # firewall - see the variable's description for when that stops being true.
  appliance_mode_support = var.egress_attachment_appliance_mode_support

  tags = {
    Name = var.egress_vpc_attachment_name
  }
}
resource "aws_ec2_transit_gateway_vpc_attachment" "app_vpc_tgw_attachment" {
  transit_gateway_id = module.transit_gateway.transit_gateway_id
  vpc_id             = module.app_vpc.vpc_id
  subnet_ids         = module.app_vpc.private_subnet_ids
  tags = {
    Name = var.app_vpc_attachment_name
  }
}
# The hub's only static route: everything goes to the egress VPC.
#
# transit_gateway_route_table_id is the single attribute that replaced the _monolithic template's
# Lambda-backed custom resource, which existed only to discover this id because CloudFormation does not
# return it. modules/transit_gateway/main.tf has the whole story.
#
# Without this route, traffic from the spoke reaches the gateway and is blackholed there. The spoke's own
# default route still points at the gateway, so the instance sees a connection that times out with nothing
# in any log - the firewall is never reached, so even its flow log is silent.
#
# The reverse direction is not declared anywhere, and should not be: with
# default_route_table_propagation enabled, both VPC CIDRs are propagated into this same table
# automatically, which is what gets replies back to the spoke.
resource "aws_ec2_transit_gateway_route" "tgw_static_route" {
  destination_cidr_block         = var.transit_gateway_default_route_cidr_block
  transit_gateway_attachment_id  = aws_ec2_transit_gateway_vpc_attachment.egress_vpc_tgw_attachment.id
  transit_gateway_route_table_id = module.transit_gateway.association_default_route_table_id
}
# Step one of the outbound path: the spoke VPC sends everything to the gateway.
#
# This is the route that makes the spoke VPC's egress centralized. Remove it and the instance can reach
# nothing outside its own VPC - not the package repositories, not the SSM endpoints, so not even the shell
# used to diagnose it.
resource "aws_route" "app_default_to_transit_gateway" {
  route_table_id         = module.app_vpc.route_table_id
  destination_cidr_block = var.transit_gateway_default_route_cidr_block
  transit_gateway_id     = module.transit_gateway.transit_gateway_id

  # transit_gateway_id references the gateway, not this VPC's attachment to it, so the graph orders this
  # after a gateway the VPC may not be attached to yet - and EC2 rejects a route to an unattached transit
  # gateway. The _monolithic template carried the same edge for the same reason (rules.md D-1).
  depends_on = [aws_ec2_transit_gateway_vpc_attachment.app_vpc_tgw_attachment]
}
# The return path, and the one route in this project whose absence is hardest to diagnose.
#
# A reply arrives at the NAT gateway, which rewrites the destination back to the spoke address. The NAT
# gateway sits in a public subnet, so the public route table is consulted for that spoke address - and
# without this route the only match is the egress VPC's local route, so the packet is dropped inside the
# egress VPC. From the instance every connection then hangs, while the firewall's flow log shows the
# outbound half passing inspection. It reads exactly like a firewall problem and is not one.
#
# The destination comes from the spoke VPC module's output rather than from var.app_vpc_cidr_block, so the
# route cannot name a block the VPC does not have (rules.md B-5).
resource "aws_route" "egress_public_to_app_via_transit_gateway" {
  route_table_id         = module.egress_vpc.public_route_table_id
  destination_cidr_block = module.app_vpc.vpc_cidr_block
  transit_gateway_id     = module.transit_gateway.transit_gateway_id

  # Same reasoning as above: the reference is to the gateway, not to this VPC's attachment (rules.md D-1).
  depends_on = [aws_ec2_transit_gateway_vpc_attachment.egress_vpc_tgw_attachment]
}
# Step two: traffic arriving from the gateway is sent to the firewall endpoint in its own zone.
#
# These two routes are the firewall. Nothing else puts it in the path - the endpoint is a route table
# target and traffic does not find it on its own. Point these at the NAT gateways instead and everything
# works perfectly, nothing is inspected, and the only evidence is an empty flow log.
#
# Written out per zone rather than generated from a map, so the pairing is on adjacent lines: route table a
# names endpoint a. Crossing them is not an error and nothing reports it - the traffic is still inspected,
# but it crosses a zone boundary to reach the firewall, is billed for it, and leaves from the other zone's
# NAT gateway address. The egress check in the outputs is what detects that: the address it reports would
# be the wrong zone's.
#
# The endpoint ids are resolved by subnet inside the firewall module rather than taken from a list, because
# the API returns a firewall's endpoints in no meaningful order - that unordered list is the whole reason
# the _monolithic template declared VPC endpoint associations, and why they are gone. See
# modules/network_firewall/main.tf.
resource "aws_route" "egress_peering_a_default_to_firewall" {
  route_table_id         = module.egress_vpc.peering_route_table_a_id
  destination_cidr_block = var.transit_gateway_default_route_cidr_block
  vpc_endpoint_id        = module.network_firewall.firewall_endpoint_a_id
}
resource "aws_route" "egress_peering_b_default_to_firewall" {
  route_table_id         = module.egress_vpc.peering_route_table_b_id
  destination_cidr_block = var.transit_gateway_default_route_cidr_block
  vpc_endpoint_id        = module.network_firewall.firewall_endpoint_b_id
}
module "key_pair" {
  source = "./modules/key_pair"

  key_name        = var.key_pair_name
  key_name_prefix = "${var.project_name}-"
  rsa_bits        = var.key_pair_rsa_bits

  # This module uses nothing from either VPC and does not need one to create a key pair. It waits anyway,
  # so that every module in this root is behind both VPC modules and there is no exception for the next
  # reader to judge (rules.md D-3).
  depends_on = [module.egress_vpc, module.app_vpc]
}
module "vscode_ec2" {
  source = "./modules/vscode_ec2"

  vpc_id = module.app_vpc.vpc_id
  # The zone a private subnet. Which zone matters: the egress check compares the address the internet saw
  # against this zone's NAT gateway, and that comparison is the only way to see from outside that the
  # transit gateway kept the flow in one zone.
  subnet_id = module.app_vpc.private_subnet_a_id
  ami_id    = data.aws_ssm_parameter.al2023_ami_id.insecure_value
  key_name  = module.key_pair.key_name

  instance_name       = var.workbench_instance_name
  instance_type       = var.workbench_instance_type
  security_group_name = var.workbench_security_group_name
  egress_cidr_blocks  = var.workbench_egress_cidr_blocks
  ingress_cidr_blocks = var.workbench_ingress_cidr_blocks
  iam_policy_arns     = var.workbench_iam_policy_arns
  code_server_port    = var.code_server_port
  code_server_version = var.code_server_version
  dnf_packages        = var.workbench_dnf_packages

  # Lets the association below know when the bootstrap has finished (rules.md D-5/H-2). The module touches
  # <path>/userdata as its very last step.
  marker_file_path = var.marker_file_path

  # The longest depends_on in this root, and every entry is load-bearing.
  #
  # cloud-init starts dnf within seconds of the launch, and this instance has no path to the internet until
  # the entire chain exists: the spoke's default route, both attachments, the gateway's static route, both
  # firewall endpoints with the routes that reach them, and the NAT gateways. Value references give almost
  # none of that - subnet_id orders this after one subnet, key_name after the key pair, and nothing after
  # any route (rules.md D-2/D-3).
  #
  # Losing that race does not fail the apply. The instance reaches running, every network call in the
  # bootstrap times out, code-server is never installed, and the README association then waits for a marker
  # that will never be written until its timeout expires. The _monolithic template carried the same list on
  # its aws_instance for the same reason.
  #
  # Destroy runs it in reverse, which is the other half: the instance is removed before the routes and the
  # firewall it depends on, rather than being left stranded while they disappear.
  depends_on = [
    module.app_vpc,
    module.egress_vpc,
    module.key_pair,
    module.network_firewall,
    aws_ec2_transit_gateway_vpc_attachment.app_vpc_tgw_attachment,
    aws_ec2_transit_gateway_vpc_attachment.egress_vpc_tgw_attachment,
    aws_ec2_transit_gateway_route.tgw_static_route,
    aws_route.app_default_to_transit_gateway,
    aws_route.egress_public_to_app_via_transit_gateway,
    aws_route.egress_peering_a_default_to_firewall,
    aws_route.egress_peering_b_default_to_firewall,
  ]
}
locals {
  # Every output this project exposes, defined once. outputs.tf projects these and the README written onto
  # the workbench renders them, so no value expression is written twice (rules.md B-5/H-2). Adding an entry
  # here is what makes an output possible, which is what keeps the README from falling behind outputs.tf.
  #
  # The _monolithic template had no outputs at all - twenty-nine resources and nothing to read afterwards -
  # so all of these are new. They are weighted towards commands rather than values on purpose: almost
  # nothing that matters about this project is a Terraform attribute. Whether the firewall is serving,
  # whether both endpoints came up, which NAT gateway a flow actually left from and whether a packet was
  # inspected on the way are all runtime facts, and the map's order is the order to check them in.
  outputs = {
    vscode_port_forward_command = {
      order       = 1
      title       = "1. Open the workbench"
      description = "Leave this running in a terminal, then open the URL below. There is no other way in: the workbench is in a VPC with no internet gateway, which is exactly the property that forces its traffic through the firewall. The forward is terminated by the SSM agent on the instance against its own loopback address, so it crosses no security group - which is why the group has no inbound rule"
      value       = module.vscode_ec2.port_forward_command
    }
    vscode_url = {
      order       = 2
      title       = "The IDE, once the forward is up"
      description = "localhost, because the port forward terminates locally. No password - code-server runs with auth none, which is acceptable only because it listens on loopback and the session that reaches it was authorized by IAM"
      value       = module.vscode_ec2.vscode_url
    }
    session_command = {
      order       = 3
      title       = "A shell without the IDE"
      description = "Faster than the port forward when all that is wanted is to run one of the checks below"
      value       = module.vscode_ec2.session_command
    }
    firewall_status_command = {
      order       = 4
      title       = "2. Is the firewall serving?"
      description = "Run this before trusting any result below. Terraform returns from apply once the firewall resource exists, which is several minutes before its endpoints are ready - a drop test run too early passes for the wrong reason. READY and IN_SYNC is the answer to wait for"
      value       = module.network_firewall.firewall_status_command
    }
    firewall_endpoints_command = {
      order       = 5
      title       = "3. Did an endpoint come up in each zone?"
      description = "One line per zone, with the endpoint id, its subnet and its status. Two READY lines is healthy. One means a zone's traffic is being routed at an endpoint that is not serving, which drops silently - and the two subnets here must be the two dedicated firewall subnets, not the attachment subnets"
      value       = module.network_firewall.firewall_endpoints_command
    }
    firewall_endpoint_ids = {
      order       = 6
      title       = "The endpoint ids, by subnet"
      description = "What the two attachment route tables have to name as their 0.0.0.0/0 target, one line per firewall subnet. Compare against the next entry: a route pointing at the other zone's endpoint is not an error and nothing reports it"
      # Flattened to a string rather than left as a map. Every value in this map has to have the same type,
      # because readme_ordered re-keys it into a single map to sort it and a map has one element type - a
      # mixture of strings and maps fails the plan with an inconsistent-types error rather than rendering.
      value = join("   ", [for subnet_id, endpoint_id in module.network_firewall.firewall_endpoint_ids : "${subnet_id} -> ${endpoint_id}"])
    }
    inspection_route_check_command = {
      order       = 7
      title       = "4. Do the attachment route tables point at the firewall?"
      description = "Prints each attachment route table's name next to the target of its default route. Both targets must be vpce- ids and must match the zone in the table's name. A NAT gateway id here means traffic reaches the internet without being inspected, which breaks nothing and demonstrates nothing"
      value       = "aws ec2 describe-route-tables --route-table-ids ${module.egress_vpc.peering_route_table_a_id} ${module.egress_vpc.peering_route_table_b_id} --query 'RouteTables[].[Tags[?Key==`Name`].Value|[0],Routes[?DestinationCidrBlock==`0.0.0.0/0`].GatewayId|[0]]' --output text"
    }
    egress_address_command = {
      order       = 8
      title       = "5. Where does traffic actually leave from?"
      description = "Run this on the workbench. The single address it prints is the end-to-end test of the whole chain, and the next two entries say what the answer should be"
      value       = module.vscode_ec2.egress_address_command
    }
    nat_gateway_public_ips = {
      order       = 9
      title       = "The two NAT gateway addresses, by zone"
      description = "The command above must return one of these, and specifically the one for the workbench's own zone. The other zone's address means the transit gateway crossed a zone boundary; an address that is neither means traffic is leaving by a path this project does not control, which is what a public subnet or an internet gateway in the spoke VPC would cause"
      value       = join("   ", [for zone, address in module.egress_vpc.nat_gateway_public_ips : "${zone} = ${address}"])
    }
    workbench_availability_zone = {
      order       = 10
      title       = "The workbench's zone"
      description = "Which of the two addresses above is the expected one"
      value       = module.vscode_ec2.availability_zone
    }
    blocked_dns_command = {
      order       = 11
      title       = "6. The DNS block"
      description = "A query sent to a public resolver, which should time out. It leaves the VPC, so the stateful rules see it and drop port 53 in both protocols"
      value       = module.vscode_ec2.blocked_dns_command
    }
    allowed_dns_command = {
      order       = 12
      title       = "The control for it"
      description = "The same name resolved through the Amazon resolver, which should answer. That query matches the VPC's local route and never reaches the firewall. Run the two together: one answering and one hanging is a firewall drop, both hanging is broken DNS, and both answering means the stateful engine is not being consulted - check the policy's stateless default action"
      value       = module.vscode_ec2.allowed_dns_command
    }
    blocked_ping_command = {
      order       = 13
      title       = "7. The ICMP block"
      description = "100% packet loss is the pass condition. The stateless rule's action is aws:drop, which discards silently, so there is no rejection to distinguish this from a routing black hole - the alert log below is what distinguishes them"
      value       = module.vscode_ec2.blocked_ping_command
    }
    firewall_alert_log_command = {
      order       = 14
      title       = "8. What the firewall dropped"
      description = "The direct evidence that the rules fired, rather than something upstream failing. The ping should appear here as a stateless drop and the public-resolver query as a stateful one. An empty tail while traffic is definitely blocked means the traffic never reached the firewall - go back to entry 4"
      value       = module.network_firewall.alert_log_command
    }
    firewall_flow_log_command = {
      order       = 15
      title       = "9. What the firewall passed"
      description = "The other half, and the one that proves the traffic which succeeded went through the firewall rather than around it. A curl that returns a NAT gateway address but leaves no record here is traffic bypassing inspection. Neither log group exists at all if firewall_log_types was emptied, which is the _monolithic template's configuration"
      value       = module.network_firewall.flow_log_command
    }
    transit_gateway_route_table_command = {
      order       = 16
      title       = "10. The hub's routing table"
      description = "Three active routes is healthy: the static 0.0.0.0/0 pointing at the egress VPC's attachment, plus both VPC CIDRs propagated automatically. A missing spoke CIDR explains traffic that leaves and never comes back, and it means propagation is off rather than a route being wrong"
      value       = module.transit_gateway.route_table_command
    }
    transit_gateway_id = {
      order       = 17
      title       = "Transit gateway id"
      description = "The hub both VPC route tables name as a target"
      value       = module.transit_gateway.transit_gateway_id
    }
    transit_gateway_association_default_route_table_id = {
      order       = 18
      title       = "Default association route table id"
      description = "The value the original looked up with a Lambda function, an IAM role and an inline ec2:* policy, because CloudFormation does not return it. It is an attribute of the gateway in Terraform, so all of that is deleted - see modules/transit_gateway/main.tf"
      value       = module.transit_gateway.association_default_route_table_id
    }
    firewall_name = {
      order       = 19
      title       = "Firewall name"
      description = "The handle every describe-firewall call above takes"
      value       = module.network_firewall.firewall_name
    }
    firewall_log_group_names = {
      order       = 20
      title       = "Firewall log groups"
      description = "One per enabled log type. An empty value means logging is off, and every drop in this project then becomes indistinguishable from a routing mistake - which is the _monolithic template's configuration"
      value       = join("   ", [for log_type, group_name in module.network_firewall.log_group_names : "${log_type} = ${group_name}"])
    }
    egress_vpc_id = {
      order       = 21
      title       = "Egress VPC id"
      description = "The inspection VPC: public, attachment and firewall subnets in each of two zones"
      value       = module.egress_vpc.vpc_id
    }
    app_vpc_id = {
      order       = 22
      title       = "Spoke VPC id"
      description = "The protected VPC. It has no internet gateway, which is the property that makes the inspected path the only path"
      value       = module.app_vpc.vpc_id
    }
    workbench_instance_id = {
      order       = 23
      title       = "Workbench instance id"
      description = "What the port forward and the session command target"
      value       = module.vscode_ec2.instance_id
    }
    workbench_private_ip = {
      order       = 24
      title       = "Workbench private address"
      description = "Its only address. There is no public one, and giving it one would take it out of the inspected path"
      value       = module.vscode_ec2.private_ip
    }
    private_key_command = {
      order       = 25
      title       = "Private SSH key"
      description = "Retrieves the generated key from Parameter Store, which is where CloudFormation would have put it. A command rather than the key, so terraform output does not print it. Close to unusable here on purpose - there is no inbound path to this instance, so Session Manager is the way in"
      value       = module.key_pair.private_key_command
    }
    cloud_init_log_command = {
      order       = 26
      title       = "Bootstrap log for the workbench"
      description = "Every line of the user data, with set -x. First place to look when the IDE does not answer: connection timeouts on dnf and wget here mean the instance never had outbound access, which points at the security group's egress rule or an incomplete egress chain rather than at the firewall's rules"
      value       = module.vscode_ec2.cloud_init_log_command
    }
  }
  # Iterating local.outputs directly would order the sections by key, which puts "5. Where does traffic
  # actually leave from?" above "1. Open the workbench". Re-keying by the order field and taking values()
  # sorts by that instead - values() returns a map's values ordered by key - so the README reads in the
  # order the checks are meant to be run, and the order stays fully determined by the configuration rather
  # than shuffling between applies.
  readme_ordered = values({
    for key, entry in local.outputs : format("%02d-%s", entry.order, key) => entry
  })
  # Rendered from the same map, so an added output appears here without anyone remembering to edit two
  # places (rules.md H-2).
  readme_body = join("\n", concat(
    ["# ${var.project_name}", ""],
    flatten([for entry in local.readme_ordered : [
      "## ${entry.title}", "", entry.description, "", "```", entry.value, "```", "",
    ]]),
  ))
}
# The work happens inside code-server in a browser, where "terraform output" does not exist, so every
# output above is also written to a README in the home directory the IDE opens (rules.md H-2). Combining
# several modules' outputs is the root's job, so this lives here rather than inside the instance module,
# which never learns what gets written into its home directory (rules.md C-1).
#
# It needs the instance to be an SSM target, which needs the agent registered, which needs the egress chain
# to be complete - the agent reaches the SSM endpoints through the transit gateway, the firewall and a NAT
# gateway like everything else on this host. That dependency is carried by the instance module's own
# depends_on list rather than repeated here.
resource "aws_ssm_association" "vscode_readme" {
  name                             = "AWS-RunShellScript"
  wait_for_success_timeout_seconds = var.readme_timeout_seconds

  targets {
    key    = "InstanceIds"
    values = [module.vscode_ec2.instance_id]
  }

  parameters = {
    # The until loop is what orders this after the bootstrap - not depends_on, which only orders it after
    # the instance's create call returns, and not wait_for_success_timeout_seconds, which is a deadline
    # rather than a dependency (rules.md D-5). The marker path comes back out of the module it was passed
    # into, so it is defined in exactly one place (rules.md B-5).
    #
    # SSM runs as root, hence the chown - without it the file is not editable from the IDE. The heredoc
    # delimiter is quoted and deliberately unlikely to appear in the body: Terraform has already
    # substituted every value, so the shell has no reason to touch a dollar sign or a backtick in a README
    # full of CLI commands - and this one is full of JMESPath expressions that contain both.
    #
    # If this file were saved with CRLF line endings the terminator below would be TFREADME\r, which the
    # shell does not accept as a terminator: the heredoc would run to the end of the script, nothing would
    # execute, and the association would fail with "unexpected state 'Failed'" after about a hundredth of a
    # second (rules.md A-4).
    commands = <<-EOT
      until [ -f ${module.vscode_ec2.marker_file_path}/userdata ]; do sleep 10; done
      cat > /home/ec2-user/README.md << 'TFREADME'
      ${local.readme_body}
      TFREADME
      chown ec2-user:ec2-user /home/ec2-user/README.md
      touch ${module.vscode_ec2.marker_file_path}/vscode_readme
      EOT
  }
}
