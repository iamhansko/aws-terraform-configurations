# The instance that fills the website bucket, and nothing else.
#
# Named site_seeder rather than bastion, which is what the _monolithic template called it
# (aws_instance.bastion_ec2, tagged bastion-ec2, with an Ec2AdminProfile instance profile). Nothing
# connects through it or to it: the template gave it no key pair, put it in the VPC's default security
# group - which has no rule allowing anything in from outside - and opened no port. Its userdata downloads
# a zip from GitHub, unpacks it into S3 with a content type per file extension, writes the backend's URL
# into an object the page fetches, uploads the hint files, and exits. Then a Lambda function terminates it.
# That is a one-shot content seeder, and calling it a bastion sends the next reader looking for a way in
# that was never there.
resource "aws_security_group" "site_seeder_ec2" {
  name        = var.security_group_name
  description = var.security_group_description
  vpc_id      = var.vpc_id
  tags = {
    Name = var.security_group_name
  }
}
# Standalone rule resources rather than inline ingress/egress blocks (rules.md F-2), and this project is
# the dangerous version of that rule rather than the routine one.
#
# The _monolithic template declared no security group at all - it attached the VPC's default group, which
# allows all traffic from itself and all traffic outbound. A conversion that replaces that with a named
# group and copies across "the rules the template had" copies across nothing, because the template named
# none, and an aws_security_group with no egress rule has no outbound access: inline ingress/egress blocks
# are attributes-as-blocks and authoritative over the whole group, so an omitted egress block does not
# inherit EC2's default allow-all, it revokes it.
#
# That exact mistake broke 101_ubuntu_xrdp and was found twice in 103_ecs_volumes, and here it would be
# worse to diagnose than in either. Nothing about the apply would fail. The instance would launch, boot,
# and sit there unable to reach github.com or the S3 API, so the bucket would stay empty and the website
# endpoint would answer 404 to everything - with terraform apply reported as successful, every resource
# green, and the only evidence a "Temporary failure in name resolution" line in the console output of an
# instance a Lambda function has already terminated.
#
# So the egress rule below is explicit and its absence would be visible in a plan as a missing resource.
resource "aws_vpc_security_group_egress_rule" "site_seeder_ec2_egress" {
  security_group_id = aws_security_group.site_seeder_ec2.id
  description       = "All outbound - the seeder fetches the game zip over HTTPS and PUTs it to the S3 API"
  ip_protocol       = "-1"
  cidr_ipv4         = var.egress_cidr_ipv4
}
# Normally none. Empty is the correct state for this group: there is nothing listening on the instance and
# no key pair to authenticate with, so an ingress rule would open a port to a host that refuses it.
#
# It exists because debugging a failed seed means getting onto the instance, and the one route that works
# without an inbound rule is Session Manager - which is why AmazonSSMManagedInstanceCore is in the default
# policy list rather than SSH being opened here. Anyone who does add a CIDR to this still needs to add a
# key pair as well; the template never created one (rules.md B-4 - an optional feature, off by default).
resource "aws_vpc_security_group_ingress_rule" "site_seeder_ec2_ssh_ingress" {
  # toset is safe: these CIDRs are literals in configuration, so the keys are known at plan time. A list of
  # security group ids coming out of another module would have to arrive as a map instead (rules.md B-8).
  for_each = toset(var.ingress_cidr_blocks)

  security_group_id = aws_security_group.site_seeder_ec2.id
  description       = "SSH from ${each.value}"
  ip_protocol       = "tcp"
  from_port         = var.ssh_port
  to_port           = var.ssh_port
  cidr_ipv4         = each.value
}
resource "aws_iam_role" "site_seeder_ec2" {
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = {
        Service = ["ec2.amazonaws.com"]
      }
      Action = ["sts:AssumeRole"]
    }]
  })
}
# The seed write, scoped to the one bucket this instance exists to fill.
#
# The _monolithic template attached arn:aws:iam::aws:policy/AdministratorAccess to this role. rules.md A-5
# covers both halves of that: the broad policy was genuinely in the template rather than hidden in a
# bootstrap script, so narrowing it is a change to what the original did and has to be written down here -
# and the direction a conversion is allowed to move in is narrower, never wider.
#
# What the userdata actually calls is s3:PutObject, once per file in the zip plus five more times. It does
# not list the bucket, read anything back, or touch any other service. Administrator access on an instance
# in a public subnet, for that, is not a trade worth inheriting.
#
# If this list is too narrow the failure is quiet in a specific way: put_object raises AccessDenied, the
# script exits non-zero, and the website endpoint serves 404 while apply reports success. list_objects_command
# on the bucket module and seeder_console_output_command on the root are the two things that show it.
resource "aws_iam_role_policy" "site_seeder_ec2" {
  name = var.inline_policy_name
  role = aws_iam_role.site_seeder_ec2.name

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = concat(
      [{
        Effect = "Allow"
        Action = ["s3:PutObject"]
        # The bucket ARN is injected rather than looked up, so this module does not need to know which
        # bucket module built it or that one exists in this root at all (rules.md B-6).
        Resource = ["${var.bucket_arn}/*"]
      }],
      var.additional_policy_statements,
    )
  })
}
# for_each over the policy list rather than one attachment resource per policy (rules.md B-7). toset again,
# for the reason given on the ingress rule above (rules.md B-8).
resource "aws_iam_role_policy_attachment" "site_seeder_ec2" {
  for_each   = toset(var.iam_policy_arns)
  role       = aws_iam_role.site_seeder_ec2.name
  policy_arn = each.value
}
resource "aws_iam_instance_profile" "site_seeder_ec2" {
  # name_prefix, not name. The _monolithic template's literal was Ec2AdminProfile- and instance profile
  # names are account-wide, so a second copy of this project in one account fails on EntityAlreadyExists.
  name_prefix = var.instance_profile_name_prefix

  # An instance profile holds at most one role, so this attribute is a single role name string - not the
  # list CloudFormation's AWS::IAM::InstanceProfile Roles property takes. jsonencode([...]) here would send
  # the literal string ["terraform-..."] as roleName, which IAM rejects during apply while terraform
  # validate and plan both pass, because the attribute is a string either way (rules.md A-3). The
  # _monolithic file carries a hand edit and a note saying the conversion had produced exactly that.
  role = aws_iam_role.site_seeder_ec2.name
}
locals {
  # Everything the seed script needs, handed to it as one JSON document rather than interpolated line by
  # line into Python source.
  #
  # The _monolithic template built the script with echo and a single-quoted body, substituting the bucket
  # name and the function URL into the middle of it and repeating a put_object call five times for the
  # hint files. Passing a document in instead means the content lives in HCL where a plan shows it, the
  # Python stays a fixed file, and adding a hint is a map entry rather than another copy of the call.
  seed_config = {
    bucket               = var.bucket_name
    game_source_url      = var.game_source_url
    backend_config_key   = var.backend_config_key
    backend_url          = var.backend_function_url
    content_types        = var.content_types
    default_content_type = var.default_content_type
    text_objects         = var.text_objects
    image_objects        = var.image_objects
    http_timeout_seconds = var.http_timeout_seconds
  }
  # r''' around the interpolated JSON, not '''. jsonencode escapes the newlines inside the hint texts as
  # backslash-n, and a non-raw Python string literal would turn them back into real newlines inside the
  # literal - which breaks the literal, because a single-quoted triple string spanning what Python then
  # sees as the end of the JSON is a SyntaxError at import. Raw keeps the two characters for json.loads to
  # decode, which is the layer that is supposed to decode them.
  seed_script = <<-PY
    import io
    import json
    import zipfile

    import boto3
    import requests

    CONFIG = json.loads(r'''${jsonencode(local.seed_config)}''')

    s3 = boto3.client("s3")


    def content_type_for(key):
        extension = key.rsplit(".", 1)[-1].lower() if "." in key else ""
        return CONFIG["content_types"].get(extension, CONFIG["default_content_type"])


    def put(key, body, content_type):
        print("put", key, content_type, len(body), flush=True)
        s3.put_object(
            Bucket=CONFIG["bucket"], Key=key, Body=body, ContentType=content_type
        )


    def fetch(url):
        response = requests.get(url, timeout=CONFIG["http_timeout_seconds"])
        response.raise_for_status()
        return response.content


    # No try/except around any of this, which is the one behavioural change inside the script.
    #
    # The _monolithic version wrapped the whole body in "except Exception as e: print(e)". A failed
    # download, a KeyError from the extension map or an AccessDenied from S3 therefore printed one line
    # and let the interpreter exit 0 - so the cfn-signal that followed reported success and the stack
    # came up green over an empty bucket. Letting the exception out means the traceback lands in the
    # console log and the interpreter exits non-zero, which is what the shell below branches on to echo
    # the failure marker instead of the completion one.
    archive = zipfile.ZipFile(io.BytesIO(fetch(CONFIG["game_source_url"])))
    for name in archive.namelist():
        if archive.getinfo(name).is_dir():
            continue
        put(name, archive.read(name), content_type_for(name))

    # The page reads this object to find out where to ask for the password, so the backend's URL has to be
    # a value rather than a build-time constant - it does not exist until Lambda creates the function URL.
    put(
        CONFIG["backend_config_key"],
        json.dumps({"url": CONFIG["backend_url"]}),
        content_type_for(CONFIG["backend_config_key"]),
    )

    for key, url in sorted(CONFIG["image_objects"].items()):
        put(key, fetch(url), content_type_for(key))

    for key, text in sorted(CONFIG["text_objects"].items()):
        # charset only on a text/* type. The _monolithic version appended "; charset=utf-8" to a hardcoded
        # text/plain, which was right for its four files and wrong for anything else put in this map - the
        # hints are Korean, so without the charset a browser renders them as mojibake.
        media_type = content_type_for(key)
        if media_type.startswith("text/"):
            media_type += "; charset=utf-8"
        put(key, text.encode("utf-8"), media_type)
  PY
  # The package installs, assembled as lines here rather than with %{for} directives inside the heredoc.
  # A directive closed with ~} consumes the newline after itself but not the indentation of the line that
  # follows, so the rendered script comes out with the dnf lines stepped in by four and eight spaces -
  # harmless to the shell and confusing to read next to a traceback. Building the lines in a local and
  # interpolating once keeps the rendered script flush left.
  package_install_lines = join("\n", concat(
    length(var.dnf_packages) > 0 ? ["dnf install -yq ${join(" ", var.dnf_packages)}"] : [],
    [for group in var.dnf_groups : "dnf groupinstall -yq \"${group}\""],
  ))
  # The marker is what makes a failed seed findable. Everything in this script happens after apply has
  # already returned, on an instance with no inbound access that is about to be terminated, so the console
  # log is the only record - and grepping it for one string beats reading it.
  user_data = <<-EOT
    #!/bin/bash
    set -x

    dnf update -yq
    ${local.package_install_lines}
    dnf install -yq ${var.python_package}
    ln -sf /usr/bin/${var.python_package} /usr/bin/python
    python -m ensurepip --upgrade
    python -m pip install --quiet ${join(" ", var.python_requirements)}

    # A quoted heredoc rather than the echo with a single-quoted body the _monolithic template used. That
    # body contained the JSON string {\"url\" : ...} and relied on the backslashes surviving the shell
    # unquoted, which they did - but only because nothing in it ever needed a literal single quote. A
    # quoted delimiter takes the shell out of it entirely; Terraform has already substituted everything.
    cat > ${var.script_path} <<'SEEDSCRIPT'
    ${local.seed_script}
    SEEDSCRIPT

    if python ${var.script_path}; then
      echo "${var.completion_marker}"
    else
      echo "${var.failure_marker}" >&2
      exit 1
    fi

    # No cfn-signal. The _monolithic template ended with
    # "/opt/aws/bin/cfn-signal -e $? --stack <name> --resource BastionEc2", which could not work for two
    # reasons: Amazon Linux 2023 does not ship aws-cfn-bootstrap, so that path does not exist and the line
    # failed with "No such file or directory"; and there is no CloudFormation stack to signal, which the
    # conversion already records in its note that the CreationPolicy is not reproduced.
    %{if var.additional_user_data != null~}
    ${var.additional_user_data}
    %{endif~}
    EOT
}
resource "aws_instance" "site_seeder_ec2" {
  ami                         = var.ami_id
  instance_type               = var.instance_type
  subnet_id                   = var.subnet_id
  associate_public_ip_address = var.associate_public_ip_address
  vpc_security_group_ids      = concat([aws_security_group.site_seeder_ec2.id], var.extra_security_group_ids)
  iam_instance_profile        = aws_iam_instance_profile.site_seeder_ec2.name
  user_data                   = local.user_data
  tags = {
    Name = var.instance_name
  }

  # IMDSv2 required, where the _monolithic template left the default of optional. boto3 negotiates the
  # token itself, so the seed script is unaffected; the instance profile here can write to the bucket, and
  # a token-less metadata read is the shape an SSRF uses to get at that.
  metadata_options {
    http_tokens                 = var.metadata_http_tokens
    http_endpoint               = "enabled"
    http_put_response_hop_limit = var.metadata_hop_limit
  }

  # The instance profile reference orders this after the profile and the role, but not after the policy on
  # the role or the managed attachments - nothing in this resource refers to either (rules.md D-1). This
  # one matters more than most: the userdata starts calling S3 within a couple of minutes of launch, and a
  # policy that lands after the first put_object gives AccessDenied on a role that will be correct shortly
  # afterwards. Nothing retries, so the bucket keeps whatever was uploaded before the failure.
  depends_on = [
    aws_iam_role_policy.site_seeder_ec2,
    aws_iam_role_policy_attachment.site_seeder_ec2,
  ]
}
