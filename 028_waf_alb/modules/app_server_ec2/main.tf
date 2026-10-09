# The web server behind the load balancer: a small Flask application that builds SQL by string
# concatenation on purpose, so that the managed rule groups in front of it have something real to block.
#
# The _monolithic template tagged this instance app-server and tagged the other one bastion, and reading the
# two userdata scripts confirms which is which rather than relying on the tags. This one installs Flask,
# writes two Python files and serves them on the target group's port; the other installs code-server with
# authentication disabled and is the human workbench (see modules/vscode_ec2). Nothing bastions through
# either: this instance's security group opens no SSH port at all in the template, and the other one's
# opened 22 to the world rather than to anything internal. So the module keeps the name the original gave
# it - it really is the app server - and the code-server host is renamed to what rules.md H-1 and H-2 call
# a vscode_ec2.
resource "aws_security_group" "app_server_security_group" {
  name        = var.security_group_name
  name_prefix = var.security_group_name == null ? var.security_group_name_prefix : null
  description = var.security_group_description
  vpc_id      = var.vpc_id
  tags = {
    Name = coalesce(var.security_group_name, var.security_group_name_prefix)
  }
}
# Standalone rule resources rather than inline ingress/egress blocks (rules.md F-2), and the egress rule
# below is the reason rather than the usual one about controllers editing a group behind Terraform's back.
#
# The _monolithic template gave this group one inline ingress block for the application port and no egress
# block, as it did for all three of its groups. CloudFormation leaves EC2's default allow-all egress rule in
# place when a template names only SecurityGroupIngress; Terraform's inline blocks are authoritative over
# the whole group, so carrying the ingress across without adding egress does not inherit that default, it
# revokes it.
#
# On this instance that is the difference between a demo and an empty target group. Every line of the
# userdata below reaches the internet - dnf for the interpreter, pip for Flask - so with egress revoked none
# of it runs, nothing listens on the application port, the health check never passes and the load balancer
# answers 503 to the requests the web ACL allowed. terraform apply reports success and the instance reaches
# running state, and the only evidence is /var/log/cloud-init-output.log on a host that has no inbound port
# open either.
#
# This defect broke 101_ubuntu_xrdp and was found twice in 103_ecs_volumes.
resource "aws_vpc_security_group_egress_rule" "app_server_egress" {
  security_group_id = aws_security_group.app_server_security_group.id
  description       = "All outbound"
  ip_protocol       = "-1"
  cidr_ipv4         = "0.0.0.0/0"
}
# The load balancer's frontend group as the source, which is how the ALB's nodes reach the application port
# and how the health check gets through.
#
# A map keyed by a label the caller chooses, not a list. The value is another module's output - a security
# group id that does not exist at plan time - and for_each keys must be known at plan time, so
# toset(var.ingress_source_security_group_ids) fails the plan with "Invalid for_each argument: the set
# includes values derived from resource attributes that cannot be determined until apply" (rules.md B-8).
# The label also becomes part of the rule description, so a plan reads "Application port 5000 from the
# application_load_balancer security group".
resource "aws_vpc_security_group_ingress_rule" "app_server_source_group_ingress" {
  for_each = var.ingress_source_security_groups

  security_group_id            = aws_security_group.app_server_security_group.id
  description                  = "Application port ${var.app_port} from the ${each.key} security group"
  ip_protocol                  = "tcp"
  from_port                    = var.app_port
  to_port                      = var.app_port
  referenced_security_group_id = each.value
}
# Direct access to the application port, bypassing the load balancer and therefore the web ACL. Empty by
# default, which is a deliberate departure from the _monolithic template - see ingress_cidr_blocks.
#
# toset() is correct for this one: the values are configuration literals and are known at plan time
# (rules.md B-7/B-8).
resource "aws_vpc_security_group_ingress_rule" "app_server_cidr_ingress" {
  for_each = toset(var.ingress_cidr_blocks)

  security_group_id = aws_security_group.app_server_security_group.id
  description       = "Application port ${var.app_port} from ${each.value}"
  ip_protocol       = "tcp"
  from_port         = var.app_port
  to_port           = var.app_port
  cidr_ipv4         = each.value
}
# An instance role, where the _monolithic template gave this instance none at all.
#
# That omission left the host with no way in. The template opened only the application port on its security
# group - no SSH - and attached no instance profile, so the SSM agent that ships with Amazon Linux 2023 had
# no permissions to register the instance and Session Manager could not reach it either. An instance whose
# Flask process failed to start was therefore a 503 with no way to read a log.
#
# The policy list is narrow on purpose. This is an automated host rather than a human workbench, so
# rules.md A-5 applies in the direction it usually does and the default is SSM access only - not the
# AdministratorAccess the template attached to the workbench. Session Manager plus the application's own log
# is everything this instance needs to be debuggable.
resource "aws_iam_role" "app_server_iam_role" {
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = {
        Service = "ec2.amazonaws.com"
      }
      Action = "sts:AssumeRole"
    }]
  })
}
# One attachment resource for the whole list rather than one per policy (rules.md B-7). toset() is safe
# because managed policy ARNs are configuration literals and are known at plan time (rules.md B-8).
resource "aws_iam_role_policy_attachment" "app_server_iam_role" {
  for_each   = toset(var.iam_policy_arns)
  role       = aws_iam_role.app_server_iam_role.name
  policy_arn = each.value
}
resource "aws_iam_instance_profile" "app_server_instance_profile" {
  # A single role name, not the list CloudFormation's AWS::IAM::InstanceProfile Roles property takes - an
  # instance profile holds at most one role, so this attribute is a string. jsonencode([...]) here sends the
  # literal ["terraform-..."] as roleName, which IAM rejects during apply while terraform validate and plan
  # both pass because the attribute is a string either way (rules.md A-3).
  #
  # The conversion in _monolithic/common_rule_set.tf happens to be clean on this point - it already carries
  # the single role name and the note - but the trap is carried forward here because this module is where
  # someone reading the CloudFormation original would reintroduce it.
  role = aws_iam_role.app_server_iam_role.name
}
locals {
  # The two Python files, verbatim from the _monolithic template apart from the three substitutions noted
  # below. They are the demo's payload: obscure_query concatenates user input into SQL and main.py hands the
  # result straight to sqlite3, so /lookup?id=1' OR '1'='1 really does return every row. The managed rule
  # groups in front of this are not matching a harmless pattern.
  #
  # Written as locals at column zero rather than inline in the indented userdata heredoc below. An indented
  # heredoc dedents by the smallest indentation across its lines, which would survive Python's own
  # indentation today, but a single line pasted in later at a shallower indent would silently dedent the
  # whole script by less and move the inner heredoc terminators off column zero. Interpolating a multi-line
  # value avoids the question entirely: everything after its first line lands at column zero regardless of
  # where the interpolation appeared (rules.md E-9 describes the same mechanism).
  #
  # Neither file contains a dollar sign or a percent sign followed by a brace, which is the only thing HCL
  # treats specially inside a heredoc - an interpolation and a template directive respectively. The
  # f-strings use bare braces, which pass through untouched. A later edit that introduced either sequence
  # would fail the plan rather than corrupt the file, which is the good direction for that mistake.
  query_builder_py = <<QUERYBUILDER
def obscure_query(mode, **kwargs):
  if mode == "login":
      name = kwargs["name"]
      secret = kwargs["secret"]
      parts = ["SELECT", "*", "FROM", "secret_users", "WHERE"]
      parts.append(f"name='{name}'")
      parts.append("AND")
      parts.append(f"secret='{secret}'")
      return " ".join(parts)

  elif mode == "lookup":
      user_id = kwargs["id"]
      return f"""SELECT id, name, secret FROM secret_users WHERE id = {user_id}"""

  elif mode == "inspect":
      table = kwargs["table"]
      return f"""SELECT * FROM {table}"""

  return "SELECT 1"
QUERYBUILDER

  # Three changes from the template's copy, all of them about running under a service manager instead of
  # under nohup:
  #
  #   DB_FILE  absolute rather than "challenge.db". Relative, it followed the working directory - which
  #            under cloud-init is cloud-init's own, so the database was created at /challenge.db by the
  #            root-owned process the template started.
  #   port     from var.app_port, so the listener the target group forwards to and the port the app binds
  #            cannot disagree (rules.md B-5).
  #   debug    from var.flask_debug, default false. The template hardcoded True, which on a host reachable
  #            from a load balancer means the Werkzeug interactive debugger is one traceback away, and also
  #            turns on the reloader - which re-executes the script and so re-runs init(), dropping and
  #            recreating the table underneath a running request.
  #
  # The import of utils.query_builder works because Python puts the script's own directory on sys.path, not
  # because of the working directory, and utils/ needs no __init__.py since Python 3.3 treats it as a
  # namespace package. Moving main.py without moving utils/ breaks it.
  app_py = <<FLASKAPP
from flask import Flask, request, jsonify
from utils.query_builder import obscure_query
import sqlite3
import os

app = Flask(__name__)
DB_FILE = "${var.app_directory}/challenge.db"

def get_db():
    conn = sqlite3.connect(DB_FILE)
    conn.row_factory = sqlite3.Row
    return conn

def init():
    if os.path.exists(DB_FILE):
        os.remove(DB_FILE)
    conn = get_db()
    cur = conn.cursor()
    cur.execute("CREATE TABLE secret_users (id INTEGER, name TEXT, secret TEXT)")
    cur.executemany("INSERT INTO secret_users VALUES (?, ?, ?)", [
        (1, 'admin', 'supersecret'),
        (2, 'alice', 'flag{alice_flag}'),
        (3, 'bob', 'flag{bob_flag}')
    ])
    conn.commit()

@app.route("/", methods=["GET"])
def index():
    return '''
    <h2>유저관리 시스템</h2>

    <form action="/login" method="get">
        <h4>로그인</h4>
        이름: <input type="text" name="name"><br>
        비밀번호: <input type="text" name="secret"><br>
        <input type="submit" value="로그인">
    </form><hr>

    <form action="/lookup" method="get">
        <h4>ID 조회</h4>
        ID: <input type="text" name="id">
        <input type="submit" value="조회">
    </form><hr>
    '''

@app.route("/login", methods=["GET"])
def login():
    name = request.args.get("name", "")
    passwd = request.args.get("secret", "")
    q = obscure_query("login", name=name, secret=passwd)
    conn = get_db()
    try:
        res = conn.execute(q).fetchone()
        if res:
            return f"✅ 환영합니다, {res['name']} 님!"
        else:
            return "❌ 로그인 실패"
    except Exception as e:
        return f"❗ 오류 발생: {str(e)}"

@app.route("/lookup", methods=["GET"])
def lookup():
    id = request.args.get("id", "")
    q = obscure_query("lookup", id=id)
    conn = get_db()
    try:
        res = conn.execute(q).fetchall()
        return jsonify([dict(row) for row in res])
    except Exception as e:
        return jsonify(error=str(e))

if __name__ == "__main__":
    init()
    app.run(host="0.0.0.0", port=${var.app_port}, debug=${var.flask_debug ? "True" : "False"})
FLASKAPP

  # The routes this app serves, as values rather than as strings the caller restates.
  #
  # The root builds the demo's curl commands out of these and the load balancer's URL, because it is the
  # only place that holds both (rules.md C-1). Taking them from here rather than writing "/lookup" into the
  # root means a change to the app above cannot leave the probes pointing at a route that no longer exists -
  # which would show up as a 404 that looks nothing like a WAF problem.
  index_path             = "/"
  lookup_path            = "/lookup"
  lookup_query_parameter = "id"
  login_path             = "/login"

  # A systemd unit, where the _monolithic template ran "nohup python /home/ec2-user/main.py &" from
  # cloud-init.
  #
  # That line starts the app once and never again. There is no restart when the process dies, and nothing
  # starts it after a reboot - at which point the target goes unhealthy permanently and the load balancer
  # answers 503 to every request, with the app's own logs gone because nohup.out was in a working directory
  # nobody looks at. A target group whose only member is a process started by nohup is a demo that works
  # until the first stop/start.
  #
  # It also drops privileges. The template's process ran as root because cloud-init does; the application
  # port is above 1024, so there is no reason for that.
  service_unit = <<SERVICEUNIT
[Unit]
Description=Flask application behind the WAF-protected ALB
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
User=ec2-user
Group=ec2-user
WorkingDirectory=${var.app_directory}
ExecStart=/usr/bin/${var.python_command} ${var.app_directory}/main.py
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
SERVICEUNIT

  user_data = <<-EOT
    #!/bin/bash
    set -x

    dnf update -yq
    %{if length(var.dnf_groups) > 0~}
    dnf groupinstall -yq ${join(" ", [for group in var.dnf_groups : "\"${group}\""])}
    %{endif~}
    dnf install -yq ${join(" ", var.dnf_packages)}

    # No "ln -s /usr/bin/python3.13 /usr/bin/python", which the _monolithic template ran here. On Amazon
    # Linux 2023 /usr/bin/python does not exist, so that link was created and the following lines worked -
    # unlike the same trick against /usr/bin/python3, which fails with "File exists" and is the bug
    # 098_basic_lambda documents. Creating it is still the wrong move: dnf is itself a Python program bound
    # to the system interpreter, and a repointed python on a host that later installs a package is a dnf
    # that cannot import its own modules. The interpreter is named explicitly instead.
    ${var.python_command} -m ensurepip --upgrade
    ${var.python_command} -m pip install --quiet ${join(" ", var.pip_packages)}

    mkdir -p ${var.app_directory}/utils

    # Quoted heredoc delimiters, where the template used bare "<<EOF". Unquoted, the shell expands $, backticks
    # and \ inside the body - which happened to be harmless because neither of these files contains a dollar
    # sign, so the template worked by accident. Quoting makes the body literal regardless of what is edited
    # into it later, and Terraform has already substituted everything it owns before the shell sees it.
    #
    # rules.md A-4 matters twice over in this block. Saved with CRLF line endings, the terminator below
    # becomes TFQUERYBUILDER\r, which the shell does not accept - the heredoc then swallows the rest of the
    # script, nothing after this point runs, and the failure looks like an instance that booted and did
    # nothing. The delimiters are also deliberately unlikely to appear in Python source.
    cat > ${var.app_directory}/utils/query_builder.py << 'TFQUERYBUILDER'
    ${local.query_builder_py}
    TFQUERYBUILDER

    cat > ${var.app_directory}/main.py << 'TFFLASKAPP'
    ${local.app_py}
    TFFLASKAPP

    # chown the directory as well as the file, where the template chowned only main.py and left utils/ owned
    # by root. Harmless while the process ran as root; it is not harmless now that the unit runs as ec2-user
    # and the app writes its SQLite database into this directory.
    chown -R ec2-user:ec2-user ${var.app_directory}

    cat > /etc/systemd/system/${var.service_name}.service << 'TFSERVICEUNIT'
    ${local.service_unit}
    TFSERVICEUNIT
    systemctl daemon-reload
    systemctl enable --now ${var.service_name}

    # No cfn-signal call, which the template ended with. There is no CloudFormation stack here - the
    # conversion's own comment notes that the CreationPolicy it signalled is not reproduced - and
    # aws-cfn-bootstrap is not installed on Amazon Linux 2023, so that line could only ever have failed with
    # "command not found" and left cloud-init recording a non-zero exit for the whole script.
    %{if var.additional_user_data != null~}
    ${var.additional_user_data}
    %{endif~}
    EOT
}
resource "aws_instance" "app_server_ec2" {
  ami                  = var.ami_id
  instance_type        = var.instance_type
  key_name             = var.key_name
  subnet_id            = var.subnet_id
  iam_instance_profile = aws_iam_instance_profile.app_server_instance_profile.name
  # The module's own group, and only its own. Nothing is injected here: what the load balancer needs is an
  # ingress rule on this group, not a second group on the instance (rules.md B-6).
  vpc_security_group_ids = [aws_security_group.app_server_security_group.id]
  user_data              = local.user_data

  # True, as the _monolithic template had it, and in a default VPC it is load-bearing rather than cosmetic.
  # A default VPC has an internet gateway and no NAT gateway, so a subnet's route to the internet is only
  # usable by an instance that has a public address - without one, every dnf and pip line above times out
  # and the end state is identical to a revoked egress rule. The instance is still not reachable from
  # outside: its security group admits the load balancer's group and, by default, nothing else.
  associate_public_ip_address = var.associate_public_ip_address

  tags = {
    Name = var.instance_name
  }
  root_block_device {
    volume_type = "gp3"
    volume_size = var.root_volume_size
    encrypted   = true
  }
  metadata_options {
    http_endpoint = "enabled"
    # required, where the template left the provider default. Nothing on this host reads the metadata
    # service over IMDSv1: the SSM agent and the AWS SDKs all handle the token themselves, and the Flask app
    # does not call AWS at all. That matters more here than on most hosts, because the application behind
    # this endpoint evaluates attacker-controlled strings as SQL - an IMDSv1 endpoint reachable from a
    # process on this host is one step from the instance role's credentials.
    http_tokens = var.metadata_http_tokens
  }

  # The instance profile reference orders this after the profile and the role but not after the policy
  # attachment, which nothing in this resource refers to (rules.md D-1). It matters because the SSM agent
  # registers within seconds of boot: an instance that comes up before the policy lands may never appear as
  # an SSM target, and the symptom is a start-session that reports the instance is not connected rather than
  # a permissions error.
  depends_on = [aws_iam_role_policy_attachment.app_server_iam_role]
}
