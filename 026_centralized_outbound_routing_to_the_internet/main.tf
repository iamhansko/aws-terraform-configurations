# Read here rather than inside the VPC modules, and passed in as a plain string.
#
# A module carrying depends_on has every data source declared inside it deferred to apply
# (rules.md D-6), and both VPC modules carry one. Region is also the kind of value that should be the
# same everywhere in a root, and a module reading it for itself is how two modules end up disagreeing
# when an alias provider is introduced later (rules.md I-3).
data "aws_region" "current" {}

# --- The two VPCs ---
#
# rules.md D-3 is written for a root with one module called network: every other module waits for all
# of it, directly or through another module that does. This root has two VPC modules instead, so the
# rule's intent is applied with both of them as the starting points - every other module below is
# reachable from both module.egress_vpc and module.app_vpc through depends_on edges, and nothing
# starts while either VPC is still being built.
#
# That matters more here than the rule's usual case. The thing being built is a path with five hops
# in it, and the module that has to use that path - the workbench, whose first action is dnf update -
# is at the far end. A NAT gateway or a route table association that lands a few seconds late is not
# a plan error; it is a boot that downloads nothing.
#
# Neither VPC module has a depends_on of its own, and neither can have one. The attachments below
# need each VPC's subnets, while the routes those VPCs are missing need the gateway - so a
# module-level edge in either direction between a VPC and the gateway closes a cycle. The pieces that
# touch both sides live in this file for exactly that reason (see "The wiring" below).
module "egress_vpc" {
  source = "./modules/egress_vpc"

  name                          = "${var.project_name}-egress"
  region                        = data.aws_region.current.region
  availability_zone_suffixes    = var.availability_zone_suffixes
  vpc_cidr_block                = var.egress_vpc_cidr_block
  public_subnet_cidr_blocks     = var.egress_public_subnet_cidr_blocks
  attachment_subnet_cidr_blocks = var.egress_attachment_subnet_cidr_blocks
  firewall_subnet_cidr_blocks   = var.egress_firewall_subnet_cidr_blocks
  default_route_cidr_block      = var.default_route_cidr_block
}
module "app_vpc" {
  source = "./modules/app_vpc"

  name                       = "${var.project_name}-app"
  region                     = data.aws_region.current.region
  availability_zone_suffixes = var.availability_zone_suffixes
  vpc_cidr_block             = var.app_vpc_cidr_block
  private_subnet_cidr_blocks = var.app_private_subnet_cidr_blocks
}

# --- The transit gateway ---

module "transit_gateway" {
  source = "./modules/transit_gateway"

  name                           = "${var.project_name}-tgw"
  description                    = "Carries all outbound traffic from ${var.project_name}-app to ${var.project_name}-egress"
  auto_accept_shared_attachments = var.transit_gateway_auto_accept_shared_attachments

  # The module holds the gateway and nothing else, so it consumes no VPC output and this edge is
  # safe - which is the point of having split the attachments out of it (rules.md D-2/D-3).
  depends_on = [module.egress_vpc, module.app_vpc]
}

# --- The wiring ---
#
# Five resources that each need two modules, which is what makes them the root's rather than any
# module's (rules.md C-1): two attachments, the gateway's own route, and the two VPC routes that
# point at the gateway.
#
# They are also the subject of this project. The _monolithic template had six routes and every one of
# them is load-bearing in a way that produces no error when it is wrong - a missing route here is a
# timeout somewhere else, and a route pointing at the wrong target is traffic quietly bypassing the
# thing it was supposed to pass through. Routes 1, 2 and 3 are in modules/egress_vpc/main.tf; 4, 5
# and 6 are below, numbered the same way so the set can be read as one.

# The attachment that receives everything leaving the app VPC and hands it to the egress VPC.
#
# subnet_ids names the attachment tier specifically. An attachment placed in the firewall subnets
# would be rejected - AWS allows only the firewall endpoint there - but one placed in the public
# subnets would be created, report available, and send traffic into a route table whose default route
# is the internet gateway rather than a NAT gateway. Private addresses out of an internet gateway are
# dropped, with nothing logged.
resource "aws_ec2_transit_gateway_vpc_attachment" "egress_vpc" {
  transit_gateway_id = module.transit_gateway.transit_gateway_id
  vpc_id             = module.egress_vpc.vpc_id
  subnet_ids         = module.egress_vpc.attachment_subnet_ids

  # Both true, which is also the provider's default and matches the gateway's enabled defaults. Set
  # explicitly because the pair is what makes association_default_route_table_id the right table for
  # route 6 below: with association false this attachment would not be in that table, and the route
  # would be written into a table this attachment is not in - accepted by the API, and a blackhole.
  transit_gateway_default_route_table_association = true
  transit_gateway_default_route_table_propagation = true
  tags = {
    Name = "${var.project_name}-tgw-egress"
  }
}
# The attachment the app VPC's traffic enters the gateway through.
#
# Its propagation is what puts the app VPC's CIDR into the gateway's route table, and that route is
# the return half of every connection in this project. It is installed by AWS rather than by this
# configuration, so it appears in no plan - which is worth knowing, because when it is missing the
# symptom is outbound packets leaving successfully and nothing coming back.
resource "aws_ec2_transit_gateway_vpc_attachment" "app_vpc" {
  transit_gateway_id = module.transit_gateway.transit_gateway_id
  vpc_id             = module.app_vpc.vpc_id
  subnet_ids         = module.app_vpc.private_subnet_ids

  transit_gateway_default_route_table_association = true
  transit_gateway_default_route_table_propagation = true
  tags = {
    Name = "${var.project_name}-tgw-app"
  }
}
# Route 4 of 6. The app VPC's only way off the VPC.
#
# What uses it: everything in the app VPC. This table has no other non-local entry and the VPC has no
# internet gateway and no NAT gateway, so this single route is the whole of its connectivity.
#
# Missing: the workbench boots and reaches nothing. dnf update hangs, code-server is never
# downloaded, the completion marker is never touched, and the apply fails minutes later on the README
# association's timeout - which names the association, not this route.
resource "aws_route" "app_default_to_transit_gateway" {
  route_table_id         = module.app_vpc.route_table_id
  destination_cidr_block = var.default_route_cidr_block
  transit_gateway_id     = module.transit_gateway.transit_gateway_id

  # transit_gateway_id refers to the gateway, which orders this after the gateway and not after this
  # VPC's attachment to it - a separate resource whose id appears nowhere in this block
  # (rules.md D-1/D-2). A route pointing at a gateway the VPC is not attached to yet is accepted and
  # then blackholes, so the failure is a timeout rather than an error.
  depends_on = [aws_ec2_transit_gateway_vpc_attachment.app_vpc]
}
# Route 5 of 6, and the one that is easiest to leave out because it runs backwards.
#
# What uses it: the NAT gateways, when they translate a reply back to its original destination. A NAT
# gateway lives in a public subnet and therefore uses the public route table, so after it has rewritten
# a reply's destination to a 172.16 address it needs that table to know where 172.16.0.0/16 is. This
# is the route that tells it.
#
# Missing: every connection from the app VPC opens correctly and receives nothing. The outbound SYN
# traverses all four other hops, the far end answers, the reply arrives at the NAT gateway, is
# de-translated, and is then dropped because the public route table has no path to the app VPC. There
# is no error at any layer - the transit gateway's routes are active, both attachments are available,
# the NAT gateways are healthy, and every connection times out.
resource "aws_route" "egress_public_to_app_vpc" {
  route_table_id = module.egress_vpc.public_route_table_id
  # The created VPC's CIDR rather than var.app_vpc_cidr_block, so this and the app VPC read the same
  # value from one place (rules.md B-5). A literal here that drifted from the app VPC's actual block
  # would produce exactly the silent failure described above.
  destination_cidr_block = module.app_vpc.vpc_cidr_block
  transit_gateway_id     = module.transit_gateway.transit_gateway_id

  depends_on = [aws_ec2_transit_gateway_vpc_attachment.egress_vpc]
}
# Route 6 of 6. The gateway's own decision to send everything non-local to the egress VPC.
#
# This is the route whose route table id the _monolithic template needed a Lambda function to find.
# See the comment above the association_default_route_table_id output in modules/transit_gateway for
# the native attribute that replaces it and the four reasons the original function could not have
# worked.
#
# What uses it: traffic arriving from the app VPC's attachment. The companion route for the opposite
# direction - 172.16.0.0/16 towards the app VPC's attachment - is installed by propagation rather
# than written here.
#
# Missing: the gateway receives the packet, finds no matching route, and drops it. search-transit-
# gateway-routes shows one route instead of two, which is the only place this is visible.
resource "aws_ec2_transit_gateway_route" "default_to_egress_vpc" {
  destination_cidr_block         = var.default_route_cidr_block
  transit_gateway_attachment_id  = aws_ec2_transit_gateway_vpc_attachment.egress_vpc.id
  transit_gateway_route_table_id = module.transit_gateway.association_default_route_table_id

  # Both attachments, although only the egress one is referenced. A route may not be written into a
  # table for an attachment that is not associated with it yet, and the association is performed by
  # AWS when the attachment is created rather than by a resource here, so there is nothing else to
  # order against (rules.md D-1). Naming the app attachment too means the table has both associations
  # and therefore both routes - this one and the propagated return - before anything tries to use
  # them.
  depends_on = [
    aws_ec2_transit_gateway_vpc_attachment.egress_vpc,
    aws_ec2_transit_gateway_vpc_attachment.app_vpc,
  ]
}

# --- Inspection, and the workbench that tests it ---

module "network_firewall" {
  source = "./modules/network_firewall"

  name   = var.firewall_name
  vpc_id = module.egress_vpc.vpc_id
  # Keyed by zone suffix: the subnet IDs are another module's output and unknown at plan, while the
  # dynamic subnet_mapping block needs keys it can resolve during plan (rules.md B-8).
  subnet_ids                        = module.egress_vpc.firewall_subnet_ids_by_zone
  rule_group_capacity               = var.firewall_rule_group_capacity
  blocked_dns_port                  = var.firewall_blocked_dns_port
  delete_protection                 = var.firewall_delete_protection
  subnet_change_protection          = var.firewall_subnet_change_protection
  firewall_policy_change_protection = var.firewall_policy_change_protection
  enable_logging                    = var.enable_firewall_logging
  log_retention_days                = var.firewall_log_retention_days

  # module.egress_vpc because the firewall's endpoints are ENIs in that VPC's subnets. The value
  # reference above already orders this after those two subnets and after nothing else in that
  # module, which is the gap rules.md D-3 exists to close; the edge also fixes the destroy order,
  # since AWS refuses to delete a subnet while a firewall endpoint is still in it.
  #
  # module.app_vpc because the rule admits no exceptions, not because the firewall needs anything
  # from it - it is in a different VPC and reads none of its outputs. rules.md D-3 states its own
  # purpose as "no exceptions in the root": one module ordered differently from the rest means every
  # reader has to decide per module whether the omission was reasoned or forgotten, and the destroy
  # order diverges for that one module alone.
  depends_on = [module.egress_vpc, module.app_vpc]
}
module "key_pair" {
  source = "./modules/key_pair"

  key_name = var.key_name

  # Reads no VPC output at all, and still waits for both (rules.md D-3). The point of that rule is
  # that a reader does not have to decide per module whether an omission was reasoned or forgotten.
  depends_on = [module.egress_vpc, module.app_vpc]
}
locals {
  # The workbench's extra bootstrap: the AWS CLI's default region, and a helper script holding the
  # three probes this project is for.
  #
  # The probes are a script on the host rather than three separate commands in the outputs because
  # they only mean anything together. A failed curl on its own could be a broken route, a broken NAT
  # gateway, a missing egress rule or a firewall that is working; the three answers side by side
  # separate those. The script is also where someone ends up after the port-forward, so it is next to
  # the README that tells them to run it.
  #
  # The heredoc nesting works because <<-EOT computes its indentation strip from the template's own
  # source lines only. The second and later lines of this value are placed at column zero when it is
  # interpolated into the module's user_data, so the EGRESSCHECK terminator below lands at column
  # zero there too - which is also why rules.md A-4 matters twice over here: a CR before that
  # terminator makes it EGRESSCHECK-carriage-return, the heredoc runs to the end of the script, and
  # nothing executes at all.
  workbench_user_data = <<-EOT
    aws configure set default.region ${data.aws_region.current.region}
    cat > ${var.egress_check_script_path} << 'EGRESSCHECK'
    #!/bin/bash
    # Three probes. Run them together - each one on its own is ambiguous.
    echo '== this host =='
    hostname -I
    echo
    echo '== source address the internet sees =='
    echo 'expect one of the egress VPC NAT gateway addresses, never this host own 172.16 address'
    curl -s --max-time 15 ${var.public_ip_echo_url}; echo
    echo
    echo '== name resolution through the VPC resolver =='
    echo 'expect an answer: this query is served inside the VPC and never crosses the transit gateway,'
    echo 'so the firewall stateful DNS rule cannot affect it either way'
    dig +short +time=5 +tries=1 example.com. || echo '(no answer)'
    echo
    echo '== name resolution through an external resolver =='
    echo 'the firewall stateful rule group drops this. An answer here means the packet never reached'
    echo 'the firewall - which is what the current route tables do. See README section on inspection'
    dig +short +time=5 +tries=1 @${var.external_dns_resolver} example.com. || echo '(no answer)'
    echo
    echo '== icmp =='
    echo 'the firewall stateless rule group drops this. Replies here mean the same thing as above'
    ping -c 2 -W 3 ${var.external_dns_resolver} || echo '(no reply)'
    EGRESSCHECK
    chmod +x ${var.egress_check_script_path}
    chown ec2-user:ec2-user ${var.egress_check_script_path}
  EOT
}
module "vscode_ec2" {
  source = "./modules/vscode_ec2"

  name   = "${var.project_name}-app-bastion"
  vpc_id = module.app_vpc.vpc_id
  # The first zone's private subnet, as the _monolithic template launched into app-private-sn-a. A
  # private subnet in a VPC with no internet gateway, which is the only reason the probes above mean
  # anything - a host with its own route out would answer them the same way whether this project's
  # topology worked or not.
  subnet_id                  = module.app_vpc.private_subnet_ids_by_zone[var.availability_zone_suffixes[0]]
  key_name                   = module.key_pair.key_name
  instance_type              = var.vscode_instance_type
  ami_ssm_parameter_name     = var.vscode_ami_ssm_parameter_name
  root_volume_size           = var.vscode_root_volume_size
  code_server_version        = var.code_server_version
  code_server_port           = var.code_server_port
  security_group_name        = "${var.project_name}-${var.vscode_security_group_name}"
  security_group_description = "Workbench in the ${var.project_name}-app VPC, whose only route off the VPC is the transit gateway"
  ingress_cidr_blocks        = var.vscode_ingress_cidr_blocks
  iam_policy_arns            = var.vscode_iam_policy_arns
  metadata_http_tokens       = var.vscode_metadata_http_tokens
  marker_file_path           = var.marker_file_path
  additional_user_data       = local.workbench_user_data

  # The longest dependency list in this root, and every entry is a hop in the path this instance's
  # first command needs (rules.md D-2). dnf update runs within a minute of launch and goes app VPC ->
  # route 4 -> transit gateway -> route 6 -> egress attachment subnet -> route 2 or 3 -> NAT gateway
  # -> route 1 -> internet gateway. Nothing in the module's arguments mentions any of it.
  #
  # The _monolithic template expressed the same thing with one edge - its instance carried
  # depends_on = [aws_ec2_transit_gateway_route.tgw_static_route] - which covered route 6 and left
  # routes 1 to 5 to chance. The failure when one of them loses the race is not an error: the
  # instance boots, downloads nothing, never touches its marker, and the apply ends on the README
  # association's timeout.
  #
  # module.egress_vpc is named directly as well, although routes 1 to 3 already reach it, because
  # this is the module furthest from both VPCs and the rule admits no gaps (rules.md D-3).
  depends_on = [
    module.app_vpc,
    module.egress_vpc,
    module.key_pair,
    aws_route.app_default_to_transit_gateway,
    aws_route.egress_public_to_app_vpc,
    aws_ec2_transit_gateway_route.default_to_egress_vpc,
  ]
}
locals {
  # Every output this project exposes, defined once (rules.md H-2). outputs.tf projects these and the
  # README association below renders the same map onto the instance, so no value expression exists
  # twice - and an output is only possible if there is an entry here to project, which is what keeps
  # the README from falling behind.
  #
  # The _monolithic template had no outputs at all, so all of this is new. Most of it is commands
  # rather than values, and that is not a shortcut: the questions this project raises - does traffic
  # leave through the egress VPC, does the firewall see any of it - are answered by the running
  # system and not by anything Terraform holds in state.
  outputs = {
    port_forward_command = {
      order       = 1
      title       = "1. Open the IDE"
      description = "Forwards code-server to localhost, then open http://localhost:${var.code_server_port}. The only route to it: the instance is in a private subnet of a VPC with no internet gateway, so there is no URL to publish and no security group rule that could create one. code-server runs with auth: none, which is safe here only because the forwarded port is the credential"
      value       = module.vscode_ec2.port_forward_command
    }
    session_command = {
      order       = 2
      title       = "2. Or just a shell"
      description = "Session Manager onto the workbench. Works for the same reason the port forward does - the SSM agent dials out through the egress path, so nothing has to dial in"
      value       = module.vscode_ec2.session_command
    }
    egress_check_command = {
      order       = 3
      title       = "3. Run the three probes"
      description = "The demonstration, as one script. It prints this host's own address, the address the internet sees it as, a resolver query inside the VPC, the same query against an external resolver, and a ping. Read the five together: the first two answer whether egress is centralized, the last two answer whether the firewall is inspecting it"
      value       = var.egress_check_script_path
    }
    expected_source_addresses = {
      order       = 4
      title       = "4. What the second probe should print"
      description = "The egress VPC's NAT gateway addresses. One of these is the correct answer. The workbench's own 172.16 address coming back would mean it found some other way out, and a timeout means one of the six routes is wrong - console_output_command and the route table dumps below are where that is visible"
      value       = join(", ", values(module.egress_vpc.nat_gateway_public_ips))
    }
    firewall_inspects_egress_traffic = {
      order       = 5
      title       = "5. The firewall is NOT in the data path"
      description = "This is reproduced from the _monolithic template, not introduced here, and no AWS status check reports it: a Network Firewall endpoint only sees traffic a route table sends to it, and no route table in this project names one. The firewall subnets have no route table association at all, so they sit on the VPC's main table. Both rule groups are therefore unreachable, which is why probes four and five of the script succeed when the rules say they should fail. The three route changes that would close it are set out above aws_networkfirewall_firewall in modules/network_firewall/main.tf"
      value       = "false - endpoints exist in ${join(", ", keys(module.egress_vpc.firewall_subnet_ids_by_zone))} and nothing routes to them"
    }
    firewall_flow_log_command = {
      order       = 6
      title       = "6. Confirm it independently"
      description = "Tails the firewall's FLOW log after the probes have run. Empty output is the positive confirmation of the entry above - the firewall is up and receiving nothing. Logging is an addition to the _monolithic template, which configured none; without it an idle firewall and a bypassed one look identical"
      value       = module.network_firewall.flow_log_command
    }
    firewall_describe_command = {
      order       = 7
      title       = "The firewall's own view of itself"
      description = "READY, with one endpoint per zone. Worth seeing precisely because it says nothing about whether traffic reaches it: this is the output that makes a bypassed firewall look healthy"
      value       = module.network_firewall.describe_command
    }
    transit_gateway_routes_command = {
      order       = 8
      title       = "The gateway's routes"
      description = "Two rows expected: a static 0.0.0.0/0 to the egress VPC's attachment, which is route 6, and a propagated 172.16.0.0/16 to the app VPC's, which AWS installs and no plan shows. One row means route 6 failed; a row in blackhole state means it was written before its attachment was associated"
      value       = module.transit_gateway.routes_check_command
    }
    transit_gateway_attachments_command = {
      order       = 9
      title       = "The attachments and their subnets"
      description = "Check the subnet IDs, not just the state. An attachment in the egress VPC's public tier instead of its attachment tier reports available and silently sends private addresses at an internet gateway, which drops them"
      value       = module.transit_gateway.attachments_check_command
    }
    egress_route_tables_command = {
      order       = 10
      title       = "The egress VPC's route tables"
      description = "Three tables, not four. The public table holds routes 1 and 5; each attachment table holds its zone's route 2 or 3. The firewall subnets are absent because they have no table, which is the same finding as entry five seen from the routing side"
      value       = module.egress_vpc.route_tables_command
    }
    app_route_tables_command = {
      order       = 11
      title       = "The app VPC's route table"
      description = "One table, one non-local route: 0.0.0.0/0 to a tgw- id, which is route 4. A GatewayId or NatGatewayId appearing here would mean this VPC acquired its own way out and the probes are no longer measuring centralized egress"
      value       = module.app_vpc.route_tables_command
    }
    nat_gateway_check_command = {
      order       = 12
      title       = "The NAT gateways"
      description = "Both available. A gateway in failed state was created before the internet gateway was attached to the VPC, and that state is terminal - it does not recover when the attachment lands, so the fix is to taint it rather than to wait (rules.md D-1)"
      value       = module.egress_vpc.nat_gateway_check_command
    }
    address_plan = {
      order       = 13
      title       = "The address plan"
      description = "Which block is where. The app VPC's block is the destination of route 5 in the egress VPC's public route table, so the two have to agree - they read one variable rather than restating it (rules.md B-5)"
      value       = "app ${module.app_vpc.vpc_cidr_block} / egress ${module.egress_vpc.vpc_cidr_block} / firewall subnets ${join(", ", values(var.egress_firewall_subnet_cidr_blocks))}"
    }
    transit_gateway_route_table_id = {
      order       = 14
      title       = "The gateway's default route table"
      description = "The id the _monolithic template deployed a Lambda function, an IAM role, an inline ec2:* policy and a custom resource protocol to discover. It is an attribute of the gateway - aws_ec2_transit_gateway.association_default_route_table_id - and the function it replaces could not have returned it anyway, for four reasons listed above that output in modules/transit_gateway/outputs.tf"
      value       = module.transit_gateway.association_default_route_table_id
    }
    bootstrap_log_command = {
      order       = 15
      title       = "When the apply times out instead"
      description = "The boot log. The bootstrap runs with set -x, and a script that stops at wget means the egress path is broken rather than the instance being broken - which is the failure the README association's timeout actually reports. A log that never starts means the user data failed to parse, which on Amazon Linux usually means a CR reached a heredoc terminator (rules.md A-4)"
      value       = module.vscode_ec2.console_output_command
    }
    private_key_command = {
      order       = 16
      title       = "The generated private key"
      description = "Reproduces what CloudFormation's AWS::EC2::KeyPair does with a generated key. Nothing in this project can use it - there is no inbound rule, no public address and no route from outside the app VPC - so it is here for parity and for anything added to these VPCs later"
      value       = module.key_pair.private_key_command
    }
    workbench_instance_id = {
      order       = 17
      title       = "Workbench instance"
      description = "The one instance in this project, and the source of every probe above. Its private address is what must not come back from the public-address probe"
      value       = "${module.vscode_ec2.instance_id} at ${module.vscode_ec2.private_ip}"
    }
  }
  # Iterating local.outputs directly would order the README's sections by key. Re-keying by the order
  # field and taking values() - which returns a map's values ordered by key - sorts by that instead,
  # so a document whose first three sections are numbered steps reads in that order while staying
  # fully determined by configuration.
  readme_ordered = values({
    for key, entry in local.outputs : format("%02d-%s", entry.order, key) => entry
  })
  readme_body = join("\n", concat(
    ["# ${var.project_name}", ""],
    flatten([for entry in local.readme_ordered : [
      "## ${entry.title}", "", entry.description, "", "```", entry.value, "```", "",
    ]]),
  ))
}
# The work happens over a forwarded port inside code-server, where "terraform output" does not exist,
# so every output above is also written to the README in the home directory the IDE opens
# (rules.md H-2). That is the main reason this instance became a vscode_ec2 at all: the probes this
# project is for are shell commands, and this is where they have to be run.
#
# In the root rather than in the module, because the body is assembled from five modules' outputs and
# joining modules is the root's job (rules.md C-1) - modules/vscode_ec2 does not need to know what
# gets written into its home directory.
resource "aws_ssm_association" "vscode_readme" {
  name                             = "AWS-RunShellScript"
  wait_for_success_timeout_seconds = var.readme_timeout_seconds
  targets {
    key    = "InstanceIds"
    values = [module.vscode_ec2.instance_id]
  }
  parameters = {
    # The until loop is what orders this after the bootstrap - not depends_on, which only orders the
    # association against the instance resource, and not wait_for_success_timeout_seconds, which is a
    # deadline rather than a condition (rules.md D-5). The marker is touched as the last line of the
    # user data, after code-server and the probe script, so waiting on it waits for all of it.
    #
    # The marker path is read back from the module's output rather than from var.marker_file_path, so
    # the instance and this command cannot be given different paths (rules.md B-5).
    #
    # SSM runs as root, hence the chown - without it the file is not editable from the IDE. The
    # heredoc delimiter is quoted and chosen not to appear in the body: Terraform has substituted
    # every value already, so the shell has no reason to touch a "$" or a backtick in a README full
    # of CLI commands.
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
