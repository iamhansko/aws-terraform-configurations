data "aws_region" "current" {}
# The AMI id, from the public parameter AWS maintains for the latest Amazon Linux 2023 image.
#
# insecure_value rather than value: the provider marks any SSM parameter's value sensitive whatever its
# type, and a sensitive value cannot be used for an instance's ami attribute without nonsensitive().
# insecure_value is the provider's own accessor for a parameter that is not a secret, and a public AMI id is
# not one.
#
# Read here and handed to both instance modules as an id, so neither module has to know where it came from
# (rules.md B-6).
data "aws_ssm_parameter" "al2023_ami_id" {
  name = var.al2023_ami_ssm_parameter_name
}
# The network, which this project does not create.
#
# The _monolithic template took DefaultVpcId and two subnet ids as stack parameters with no defaults - so it
# did not create a VPC either, it just made whoever ran it look the ids up. There is no network module here
# for the same reason the template had none: a VPC is not what this project demonstrates, and a web ACL in
# front of a load balancer behaves identically in the default VPC and in a purpose-built one.
#
# Both lookups live in the root and both are therefore read during plan, which is what makes
# local.public_subnet_ids a known value that can be sorted and indexed. That placement is the point of
# rules.md D-6: a module carrying depends_on has its data sources deferred to apply, so the same two blocks
# inside the load balancer module - which does carry ordering - would come back unknown, and anything built
# from them with for_each or count would fail the plan with "will be known only after apply". Nothing in
# this project indexes a module-internal data source, because no module here declares one at all.
data "aws_vpc" "default" {
  count = var.vpc_id == null ? 1 : 0

  default = true
}
data "aws_subnets" "default" {
  count = var.public_subnet_ids == null ? 1 : 0

  filter {
    name   = "vpc-id"
    values = [var.vpc_id != null ? var.vpc_id : one(data.aws_vpc.default[*].id)]
  }
  # default-for-az rather than just the VPC, so this returns the one subnet per availability zone that AWS
  # created with the default VPC and not any extra subnet somebody added to it later. Those extras are often
  # private, and an internet-facing load balancer placed in one fails to serve while reporting nothing.
  filter {
    name   = "default-for-az"
    values = ["true"]
  }
}
locals {
  # one() rather than a bare [0] index: with count zero the splat is an empty tuple and one() returns null,
  # so the branch that is not taken cannot raise "index 0 out of range" while the conditional is evaluated.
  vpc_id = var.vpc_id != null ? var.vpc_id : one(data.aws_vpc.default[*].id)

  # sort() to make the order deterministic, which matters because of the next local rather than because of
  # the load balancer.
  #
  # The data source hands back a list in whatever order DescribeSubnets answered in; the provider does not
  # sort it and AWS does not document that order as stable. aws_lb takes these as a set, so a reordering
  # would be invisible there - but local.app_subnet_id below indexes the list, and subnet_id forces instance
  # replacement. Without sort(), a reordered API response is an apply that rebuilds both instances while
  # nothing in the configuration changed.
  public_subnet_ids = sort(var.public_subnet_ids != null ? var.public_subnet_ids : one(data.aws_subnets.default[*].ids))

  # Both instances in one subnet, as the _monolithic template placed them - it passed
  # DefaultVpcPublicSubnet1Id to both. The load balancer spans all of them, which is what satisfies the
  # two-availability-zone requirement; the targets do not have to.
  app_subnet_id = local.public_subnet_ids[0]
}
module "key_pair" {
  source = "./modules/key_pair"

  key_name_prefix = "${var.project_name}-"

  # No depends_on, which is worth a sentence because most roots in this repository carry
  # depends_on = [module.network] on exactly this module - 098_basic_lambda/boto3_sqs_client puts one on
  # its key_pair with a note explaining that a key pair needs no VPC and waits anyway.
  #
  # rules.md D-3 asks for that so there is no per-module judgement call left to make, but it is conditioned
  # on the root having a network module. This root has none (see the data sources above), as
  # 097_cloudfront_s3_static_website and 098_basic_lambda/boto3_s3_client also do not, so the letter of the
  # rule has nothing to attach to and the ordering that remains is the real dependency ordering, expressed
  # on the modules below. Writing down why a rule does not apply rather than leaving its absence to be
  # rediscovered is the practice 097's outputs.tf follows for H-2.
}
module "application_load_balancer" {
  source = "./modules/application_load_balancer"

  vpc_id     = local.vpc_id
  subnet_ids = local.public_subnet_ids

  listener_port       = var.listener_port
  target_port         = var.app_port
  ingress_cidr_blocks = var.load_balancer_ingress_cidr_blocks

  # name, name_prefix, target_group_name and target_group_name_prefix are deliberately not passed. The
  # module generates both names from short prefixes rather than fixing them the way the _monolithic template
  # fixed "alb" and "alb-tg", and it explains there why - a load balancer name and a target group name are
  # both unique per account and region, so the literals collided on a second deployment.

  # From a root variable rather than from module.app_server_ec2.index_path, which would be the obvious
  # single-source wiring. It cannot be done: this module's security group is the app server module's ingress
  # source, so a reference back would make the two modules depend on each other and Terraform refuses that
  # outright - "Error: Cycle: module.app_server_ec2.var..., module.application_load_balancer.output...",
  # reported by validate as well as plan. The app server module exposes index_path so the two can be
  # compared; see the comment on that module.
  health_check_path = var.health_check_path
}
module "app_server_ec2" {
  source = "./modules/app_server_ec2"

  vpc_id    = local.vpc_id
  subnet_id = local.app_subnet_id
  ami_id    = data.aws_ssm_parameter.al2023_ami_id.insecure_value
  key_name  = module.key_pair.key_name

  instance_name = var.app_server_instance_name
  instance_type = var.app_server_instance_type
  flask_debug   = var.flask_debug

  # The same number the target group was created with, read back out of that module rather than taken from
  # var.app_port again - so the port the app binds cannot drift from the port the load balancer forwards to
  # (rules.md B-5). Both ultimately come from one root variable; this makes the chain visible.
  app_port = module.application_load_balancer.target_port

  # The load balancer's frontend group as the source of the ingress rule, as a map with a key chosen here. A
  # list would fail the plan with "Invalid for_each argument", because the value is another module's output
  # and so unknown until apply, while for_each keys have to be known at plan time (rules.md B-8). The key
  # also becomes the rule's description, so a plan reads "Application port 5000 from the
  # application_load_balancer security group".
  ingress_source_security_groups = {
    application_load_balancer = module.application_load_balancer.security_group_id
  }

  # Empty by default, which closes the direct path to the application port that the _monolithic template
  # left open to the world. See the variable.
  ingress_cidr_blocks = var.app_server_ingress_cidr_blocks

  # The value references above order this after the key pair and after one security group in the load
  # balancer module, and after nothing else in either. depends_on extends that to both modules as wholes,
  # which is what "after the load balancer is built" means and what makes destroy run in the exact reverse -
  # the instance and its registration go before the listener and the target group (rules.md D-2). An
  # exception here would also leave the next reader deciding, per module, whether an omission was reasoned
  # or forgotten, which is the argument rules.md D-3 makes for roots that do have a network module.
  depends_on = [module.key_pair, module.application_load_balancer]
}
module "web_application_firewall" {
  source = "./modules/web_application_firewall"

  name                = var.web_acl_name
  metric_name         = var.web_acl_metric_name
  default_action      = var.web_acl_default_action
  managed_rule_groups = var.managed_rule_groups

  # scope is deliberately not passed. The module pins it to REGIONAL with a validation that explains why a
  # CLOUDFRONT scope web ACL cannot be associated with a load balancer and would need a us-east-1 provider
  # this root does not declare.

  # What the web ACL is put in front of, keyed by a label chosen here. A map rather than a list for the same
  # reason as the security group above: the ARN is another module's output and so unknown at plan time,
  # while for_each keys are not (rules.md B-8).
  associated_resource_arns = {
    application_load_balancer = module.application_load_balancer.arn
  }

  # The ARN reference above orders the association after the aws_lb resource and after nothing else in that
  # module - not after the listener, and not after the target group. depends_on is what makes it wait for
  # the load balancer to be finished rather than merely created.
  #
  # Two things turn on that. A web ACL in front of a load balancer with no listener filters nothing, because
  # there is no request path to filter; and on the way down the order reverses exactly, so the association
  # is removed before the listener and the load balancer are deleted rather than racing them (rules.md
  # D-2).
  depends_on = [module.application_load_balancer]
}
module "vscode_ec2" {
  source = "./modules/vscode_ec2"

  vpc_id    = local.vpc_id
  subnet_id = local.app_subnet_id
  ami_id    = data.aws_ssm_parameter.al2023_ami_id.insecure_value
  key_name  = module.key_pair.key_name

  instance_name        = var.vscode_instance_name
  instance_type        = var.vscode_instance_type
  code_server_port     = var.code_server_port
  code_server_version  = var.code_server_version
  ingress_cidr_blocks  = var.vscode_ingress_cidr_blocks
  associate_elastic_ip = var.vscode_associate_elastic_ip

  # Lets the association at the bottom of this file know when the bootstrap has finished (rules.md
  # D-5/H-2). The module touches <path>/userdata as its very last step, after code-server is installed and
  # running.
  marker_file_path = var.marker_file_path

  # Nothing on this host depends on the load balancer or the web ACL existing - it is a browser and a shell
  # - so the only real ordering is the key pair it attaches, which the key_name reference already gives it.
  # It is stated anyway for the reason given on the app server module.
  depends_on = [module.key_pair]
}
locals {
  # The registration, as a map with a key written here rather than as a bare target_id.
  #
  # The instance id is another module's output and is unknown at plan time, so a for_each over a set of ids
  # would fail with "Invalid for_each argument"; a statically keyed map puts the unknown value where it is
  # allowed to be (rules.md B-8). With one target that is a shape rather than a necessity - but it is the
  # shape that makes a second target one line, and the resource address then says which instance is
  # registered instead of saying nothing.
  target_instance_ids = {
    app_server = module.app_server_ec2.instance_id
  }
}
# The one resource in this project that joins two modules, which is why it is in the root rather than inside
# either of them (rules.md C-1).
#
# It is also what keeps those two modules from referencing each other. The app server's security group takes
# the load balancer's group as its ingress source; if the load balancer module took the instance id to
# register it, the two modules would reference each other's outputs and Terraform would refuse to build the
# graph at all - module output references resolve against the whole module, so a cycle between modules is a
# hard error rather than a resource-level one that could be untangled. terraform validate reports it as
# "Error: Cycle: ... (expand)".
resource "aws_lb_target_group_attachment" "app_server" {
  for_each = local.target_instance_ids

  target_group_arn = module.application_load_balancer.target_group_arn
  target_id        = each.value
  # From the target group's own module rather than from var.app_port, so the registration cannot name a
  # different port than the group was created with (rules.md B-5). The ELB API accepts a mismatch and the
  # consequence is a target that fails every health check, which reads as an application problem.
  port = module.application_load_balancer.target_port
}
locals {
  # The demo, built here because the root is the only place that holds both halves: the endpoint comes from
  # the load balancer module and the route and parameter name come from the app server module, which owns
  # the Python source they are defined in (rules.md C-1).
  probe_endpoint        = "${module.application_load_balancer.url}${module.app_server_ec2.lookup_path}"
  probe_query_parameter = module.app_server_ec2.lookup_query_parameter

  # -G with --data-urlencode rather than a hand-encoded query string. The injection payload contains quotes,
  # spaces and an equals sign, and a percent-encoded literal written out by hand is both unreadable and easy
  # to get subtly wrong - and a probe that arrives malformed does not match the rule, which is
  # indistinguishable from WAF not working.
  #
  # The payload is in double quotes because it contains single quotes. That is also why the payload
  # variables refuse a double quote, a backslash, a backtick and a dollar sign: those four would escape the
  # quoting of a command this project prints out for someone to paste.
  #
  # %%{http_code} and not %{http_code}, because %{ opens a template directive in HCL and curl's format
  # string uses the same two characters - written plainly the plan fails with "http_code is not a valid
  # template control keyword". The same note is in 097_cloudfront_s3_static_website/outputs.tf.
  allowed_request_command        = "curl -sS -o /dev/null -w 'allowed   : %%{http_code}\\n' -G '${local.probe_endpoint}' --data-urlencode \"${local.probe_query_parameter}=${var.demo_allowed_value}\""
  sqli_request_command           = "curl -sS -o /dev/null -w 'sqli      : %%{http_code}\\n' -G '${local.probe_endpoint}' --data-urlencode \"${local.probe_query_parameter}=${var.demo_sqli_payload}\""
  path_traversal_request_command = "curl -sS -o /dev/null -w 'traversal : %%{http_code}\\n' -G '${local.probe_endpoint}' --data-urlencode \"${local.probe_query_parameter}=${var.demo_path_traversal_payload}\""

  # All three in one paste, which is the form worth reading: the three status codes next to each other say
  # more than any one of them does. 200/403/403 is the web ACL working.
  waf_check_command = join("\n", [
    local.allowed_request_command,
    local.sqli_request_command,
    local.path_traversal_request_command,
  ])

  # The same injection sent straight at the instance, going around the load balancer and therefore around
  # the web ACL. With app_server_ingress_cidr_blocks empty - the default - this times out, which is the
  # answer this project wants. Set that variable to 0.0.0.0/0, as the _monolithic template had it, and this
  # returns 200 with the whole table in the body while the identical request through the load balancer
  # returns 403.
  app_server_direct_request_command = "curl -sS --max-time 10 -G 'http://${module.app_server_ec2.public_ip}:${module.app_server_ec2.app_port}${module.app_server_ec2.lookup_path}' --data-urlencode \"${local.probe_query_parameter}=${var.demo_sqli_payload}\""

  # The console link the _monolithic template's second output produced, rebuilt from the parameter name the
  # key_pair module hands back rather than by reassembling /ec2/keypair/<id> here (rules.md B-5). The double
  # encoding is the console's own: the path separators appear as %252F because the console reads the
  # parameter name out of its URL fragment after one decode.
  key_pair_parameter_console_url = "https://${data.aws_region.current.region}.console.aws.amazon.com/systems-manager/parameters/${replace(module.key_pair.private_key_parameter_name, "/", "%252F")}"
}
locals {
  # Every output this project exposes, defined once.
  #
  # outputs.tf projects these and the README written onto the workbench renders them, so no value expression
  # exists twice (rules.md B-5/H-2). Adding an entry here is what makes an output possible - an output
  # declared in outputs.tf with its own expression would simply be missing from the README, and nothing
  # would report it because the apply succeeds either way.
  #
  # The map's keys are the output names. order decides the README's section order, which is the order the
  # demo is run in rather than the order the resources were created.
  #
  # Most of these are commands rather than values, and that is forced rather than chosen. Whether the target
  # is healthy, whether a request is blocked, and which rule blocked it are all facts about a running
  # system; no resource attribute holds any of them, and the two outputs the _monolithic template had - a
  # code-server URL and a console link - say nothing about whether the web ACL works.
  outputs = {
    vscode_url = {
      order       = 1
      title       = "code-server"
      description = "Open the IDE here and run everything below from its terminal, which is why this instance exists. No password: code-server is configured with auth: none, so the address and vscode_ingress_cidr_blocks are the only things protecting a shell on a host whose role is AdministratorAccess. This is the _monolithic template's VsCode output"
      value       = module.vscode_ec2.vscode_url
    }
    alb_url = {
      order       = 2
      title       = "The protected endpoint"
      description = "The load balancer the web ACL is associated with. Every request in this demo goes here. A 503 from it means the target is not in service yet or at all - check the next entry before anything else"
      value       = module.application_load_balancer.url
    }
    target_health_command = {
      order       = 3
      title       = "1. Is the app server in service"
      description = "With the default health check settings a freshly registered target needs five successful checks thirty seconds apart, so this reads unhealthy for about two and a half minutes after apply returns and that is normal. Still unhealthy after that: Target.Timeout points at the security groups, Target.FailedHealthChecks at the app or at health_check_path, and an empty table means nothing was registered"
      value       = module.application_load_balancer.target_health_command
    }
    waf_check_command = {
      order       = 4
      title       = "2. The whole demo, in one paste"
      description = "Three requests to the same route through the same endpoint. 200 then 403 then 403 is the web ACL doing its job - the first is an ordinary lookup, the second is a SQL injection and the third is a path traversal. 200 across the board means the association is missing or both groups are overridden to count; 503 across the board is the target, not WAF"
      value       = local.waf_check_command
    }
    allowed_request_command = {
      order       = 5
      title       = "The allowed request on its own"
      description = "A benign row id. This is the control: it proves the endpoint serves, so that a 403 from the other two can be attributed to the rule groups rather than to anything in between"
      value       = local.allowed_request_command
    }
    sqli_request_command = {
      order       = 6
      title       = "The SQL injection on its own"
      description = "Should be 403, from AWSManagedRulesSQLiRuleSet. Drop the -o /dev/null to see the body: a 403 produced by WAF is a short AWS-branded page rather than anything the application wrote. If it returns 200 with every row of the table, the request reached the app - which is what makes this a real injection rather than a pattern match"
      value       = local.sqli_request_command
    }
    path_traversal_request_command = {
      order       = 7
      title       = "The path traversal on its own"
      description = "Should be 403, from AWSManagedRulesCommonRuleSet - its GenericLFI_QUERYARGUMENTS rule. It is here so that the two rule groups are distinguishable: with only the injection probe, a demo missing the common rule set entirely would look the same"
      value       = local.path_traversal_request_command
    }
    sampled_requests_command = {
      order       = 8
      title       = "3. Read the blocks back out of WAF"
      description = "One command per rule group plus one for the default action. This is what turns a 403 into an attributed 403: the blocked request appears under its group's metric name with the matching rule named in the sample. A 403 that appears nowhere here did not come from WAF, and that distinction is the reason this entry exists at all"
      value       = module.web_application_firewall.sampled_requests_command
    }
    blocked_request_metrics_command = {
      order       = 9
      title       = "4. Blocked request counts"
      description = "The same answer as a number rather than as samples. Run the list-metrics line first: it prints the dimension sets that exist, and the get-metric-statistics line after it assumes WebACL and Rule. Metrics lag by a minute or two, so an empty result straight after a probe is timing"
      value       = module.web_application_firewall.blocked_request_metrics_command
    }
    web_acl_for_resource_command = {
      order       = 10
      title       = "Confirm the association from the other side"
      description = "Asks the load balancer which web ACL is in front of it. Worth running before trusting any 403, and essential before trusting a 200: a web ACL that exists but is associated with nothing filters nothing, and neither the web ACL's own attributes nor terraform output would say so"
      value       = module.web_application_firewall.web_acl_for_resource_command
    }
    managed_rule_group_summary = {
      order       = 11
      title       = "What is actually configured"
      description = "The rule groups in evaluation order with their override actions and metric names. override_action=count on a group means it records matches and blocks nothing, which is the first thing to check when a probe that should be refused comes back 200"
      value       = module.web_application_firewall.managed_rule_group_summary
    }
    describe_managed_rule_group_commands = {
      order       = 12
      title       = "The individual rules inside each group"
      description = "Names, default actions and labels for every rule AWS publishes in these groups. These are the names rule_action_overrides takes, and the only reliable way to get one right - an override naming a rule a group does not contain is refused during apply with nothing in the plan to warn about it"
      value       = module.web_application_firewall.describe_managed_rule_group_commands
    }
    web_acl_arn = {
      order       = 13
      title       = "Web ACL ARN"
      description = "What every wafv2 call identifies the web ACL by. The region embedded in it is also the clearest statement that this is a REGIONAL web ACL rather than a CloudFront one"
      value       = module.web_application_firewall.web_acl_arn
    }
    web_acl_capacity = {
      order       = 14
      title       = "Capacity used"
      description = "Web ACL capacity units the two managed groups consume, computed by WAF rather than by Terraform. A web ACL is capped at 1500 by default, so this is the number that decides how many more groups will fit before the limit has to be raised"
      value       = tostring(module.web_application_firewall.web_acl_capacity)
    }
    app_server_direct_request_command = {
      order       = 15
      title       = "The bypass, and why the app port is closed"
      description = "The same injection sent straight at the instance. With app_server_ingress_cidr_blocks empty - the default here, where the _monolithic template opened the port to the world - this times out, which is the point: a web ACL on a load balancer filters what arrives through the load balancer and nothing else. Set that variable to 0.0.0.0/0 and this returns the whole table while the identical request through the endpoint returns 403"
      value       = local.app_server_direct_request_command
    }
    app_server_session_command = {
      order       = 16
      title       = "Get onto the app server"
      description = "There is no SSH ingress rule on that host and no public route to it, so this is the way in. It works because this project gives the instance an SSM role, which the _monolithic template did not - under that template an app server whose Flask process failed to start was a 503 with no log reachable by any route"
      value       = module.app_server_ec2.session_command
    }
    app_server_service_command = {
      order       = 17
      title       = "Is the app running"
      description = "Run this on the app server. A unit restarting in a loop with ModuleNotFoundError naming flask means pip never ran, which points at egress; naming utils means main.py and utils/ are no longer in the same directory. Under the original there was no unit at all - the app was started with nohup and did not survive a reboot"
      value       = module.app_server_ec2.service_status_command
    }
    app_server_cloud_init_log_command = {
      order       = 18
      title       = "App server bootstrap log"
      description = "Every line of its user data, with set -x. Connection timeouts against dnf and pip in here mean the security group has no egress rule or the instance has no public address - in a default VPC, which has an internet gateway and no NAT gateway, those amount to the same thing"
      value       = module.app_server_ec2.cloud_init_log_command
    }
    vscode_cloud_init_log_command = {
      order       = 19
      title       = "Workbench bootstrap log"
      description = "First place to look when the IDE does not answer. If you are reading this file in code-server then the bootstrap finished, because the association that wrote it waits for the bootstrap's marker before it runs"
      value       = module.vscode_ec2.cloud_init_log_command
    }
    private_key_command = {
      order       = 20
      title       = "Private SSH key"
      description = "Retrieves the generated key from Parameter Store, which is where CloudFormation puts a key pair it creates. A command rather than the key, so terraform output does not print it. Little used here: the workbench is reached in a browser and the app server through Session Manager"
      value       = module.key_pair.private_key_command
    }
    key_pair_parameter_console_url = {
      order       = 21
      title       = "The same key in the console"
      description = "This is the _monolithic template's KeyPairValue output, rebuilt from the parameter name the key_pair module reports rather than from a path reassembled here"
      value       = local.key_pair_parameter_console_url
    }
  }
  # Iterating local.outputs directly would order the README's sections by key, which puts "4. Blocked
  # request counts" above "1. Is the app server in service". Re-keying by the order field and taking
  # values() sorts by that instead - values() returns a map's values ordered by key - so the README reads in
  # the order the demo is run, and that order stays fully determined by the configuration rather than
  # shuffling between applies.
  readme_ordered = values({
    for key, entry in local.outputs : format("%02d-%s", entry.order, key) => entry
  })
  # Rendered from the same map, so an added output appears in the README without anyone remembering to edit
  # a second place (rules.md H-2).
  readme_body = join("\n", concat(
    ["# ${var.project_name}", ""],
    flatten([for entry in local.readme_ordered : [
      "## ${entry.title}", "", entry.description, "", "```", entry.value, "```", "",
    ]]),
  ))
}
# The work happens inside code-server in a browser, where "terraform output" does not exist, so every output
# above is also written to a README in the home directory the IDE opens (rules.md H-2). That matters more
# than usual in this project: almost every output is a command to be run, and a command nobody can see is a
# demo nobody can perform.
#
# This lives in the root because combining several modules' outputs is the root's job (rules.md C-1) - the
# vscode_ec2 module never learns what gets written into its home directory.
resource "aws_ssm_association" "vscode_readme" {
  name                             = "AWS-RunShellScript"
  wait_for_success_timeout_seconds = var.readme_timeout_seconds

  targets {
    key    = "InstanceIds"
    values = [module.vscode_ec2.instance_id]
  }

  parameters = {
    # The until loop is what orders this after the bootstrap. Not depends_on, which would only order it
    # after the instance's create call returns, and not wait_for_success_timeout_seconds, which is a
    # deadline rather than a dependency (rules.md D-5). The marker path comes back out of the module it was
    # passed into, so it is defined in exactly one place (rules.md B-5).
    #
    # SSM runs this as root, hence the chown - without it the file is not editable from the IDE. The heredoc
    # delimiter is quoted and deliberately unlikely to appear in the body, which matters here: the README is
    # full of shell commands containing $(date ...) substitutions and %{http_code} format strings, and an
    # unquoted delimiter would let the shell evaluate them while writing the file.
    #
    # rules.md A-4 applies with force. Saved with CRLF line endings this terminator becomes TFREADME\r,
    # which the shell does not recognise - the heredoc would run to the end of the script, nothing would
    # execute, and the apply would fail with "unexpected state 'Failed'" and no indication why.
    commands = <<-EOT
      until [ -f ${module.vscode_ec2.marker_file_path}/userdata ]; do sleep 10; done
      cat > ${module.vscode_ec2.readme_path} << 'TFREADME'
      ${local.readme_body}
      TFREADME
      chown ec2-user:ec2-user ${module.vscode_ec2.readme_path}
      touch ${module.vscode_ec2.marker_file_path}/vscode_readme
      EOT
  }
}
