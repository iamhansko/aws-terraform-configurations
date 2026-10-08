# A one-shot instance whose entire job is to run two commands no AWS API can run for Terraform:
# export the certificate ACM issued, and decrypt the private key that comes with it.
#
# Named for what it does rather than for what it is. The _monolithic template called it
# BastionEc2, which suggests a host someone connects through, and nothing connects to this one:
# there is no key pair in this project, no inbound rule below, and the instance is terminated
# before the apply finishes. It is a build step that happens to need an operating system -
# specifically it needs openssl, because ACM hands back a passphrase-encrypted PKCS#8 key and
# IAM Roles Anywhere's credential helper wants an unencrypted one.
resource "aws_security_group" "certificate_export_ec2_security_group" {
  name        = var.security_group_name
  description = var.security_group_description
  vpc_id      = var.vpc_id
  tags = {
    Name = var.security_group_name
  }
}
# No ingress rule of any kind, and that is complete rather than unfinished. Nothing reaches this
# instance inbound: there is no key pair to SSH with, the terminator Lambda that waits for the
# upload watches the bucket rather than the instance, and a Session Manager session for debugging
# arrives through the SSM agent, which connects *out* and polls. An ingress rule here would be a
# hole with nothing behind it.
#
# The egress rule, on the other hand, is mandatory, and leaving it out is the trap worth spelling
# out. The _monolithic template attached the VPC's default security group
# (aws_vpc.vpc.default_security_group_id) - a group Terraform does not manage here, which keeps the
# allow-all egress rule AWS creates with it, so the template never had to mention egress. A group
# Terraform creates is different in two ways:
#
#   - AWS adds an allow-all egress rule to every new security group, and the provider removes it.
#     A group with no egress resource is a group with no outbound access at all, not one with the
#     AWS default.
#   - Inline ingress/egress blocks are authoritative over the whole group, so naming only ingress
#     revokes egress rather than leaving it alone - which is the opposite of what
#     AWS::EC2::SecurityGroup does with SecurityGroupIngress.
#
# Either way the failure is quiet and late. apply succeeds, the instance launches, and every call
# in the bootstrap below - ACM, S3, the SSM agent's registration - hangs until it times out.
# Nothing is uploaded, so the apply eventually fails at the terminator Lambda's wait with nothing
# pointing at the network. That is how 101_ubuntu_xrdp broke, and it was found twice in
# 103_ecs_volumes (rules.md F-2).
resource "aws_vpc_security_group_egress_rule" "certificate_export_ec2_egress" {
  security_group_id = aws_security_group.certificate_export_ec2_security_group.id
  description       = "All outbound"
  ip_protocol       = "-1"
  cidr_ipv4         = "0.0.0.0/0"
}
resource "aws_iam_role" "certificate_export_ec2_iam_role" {
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
# The two calls the bootstrap actually makes, and nothing else.
#
# This is a deliberate divergence from the _monolithic template, which attached
# arn:aws:iam::aws:policy/AdministratorAccess to this role, so it is worth being precise about why
# that is allowed here (rules.md A-5).
#
# A-5's prohibition is against replacing a narrow policy you could not see - one built by a
# bootstrap script outside Terraform - with a broad managed one. That is not this case: the
# template really did name AdministratorAccess itself, so this is the other case A-5 describes,
# where narrowing is changing what the original did and the requirement is to say so here.
#
# And H-1's premise does not cover it. The broad policy on vscode_ec2 and bastion_ec2 is kept
# because those are workbenches - a person sits at them and runs arbitrary AWS commands, so
# narrowing would break the demo. Nobody ever sits at this instance. It runs one script and is
# terminated by a Lambda in the same apply, and while it runs it holds an unencrypted private key
# on its root volume that is enough to obtain the vended role's credentials. Administrator on a
# host in a public subnet holding a usable credential is a worse trade than it looks.
#
# To reproduce the template exactly, add arn:aws:iam::aws:policy/AdministratorAccess to
# iam_policy_arns; nothing else needs changing.
#
# Inline rather than aws_iam_policy plus an attachment: the policy names this role's two resources
# and is useful to nothing else, and an inline policy is scoped to the role, so unlike a managed
# policy it has no account-wide name to collide with a second copy of this project.
resource "aws_iam_role_policy" "certificate_export_ec2_iam_role" {
  name = "certificate-export"
  role = aws_iam_role.certificate_export_ec2_iam_role.name
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "ExportTheIssuedCertificate"
        Effect = "Allow"
        # The one call that makes this instance necessary. Scoped to the certificate: with it
        # missing the bootstrap stops on AccessDeniedException, and because the script runs under
        # set -e it stops before writing anything to S3 - see the comment on the script below for
        # why that ordering matters.
        Action   = "acm:ExportCertificate"
        Resource = var.certificate_arn
      },
      {
        Sid    = "WriteTheExportedFiles"
        Effect = "Allow"
        # PutObject only. This instance writes the four objects and never reads them back:
        # whether they arrived is checked by the terminator Lambda, which lists the bucket under
        # its own role. s3:GetObject used to be here for an SSM association that ran head-object
        # from this instance; that association is gone, and a host holding the private key has no
        # need to read the bucket it came from.
        Action   = "s3:PutObject"
        Resource = "${var.artifact_bucket_arn}/*"
      },
    ]
  })
}
# for_each over the managed policy list rather than one attachment per policy (rules.md B-7). toset
# is safe because these ARNs are configuration literals and so known at plan time; a set built from
# another module's output would fail with "Invalid for_each argument" (rules.md B-8).
resource "aws_iam_role_policy_attachment" "certificate_export_ec2_iam_role" {
  for_each   = toset(var.iam_policy_arns)
  role       = aws_iam_role.certificate_export_ec2_iam_role.name
  policy_arn = each.value
}
resource "aws_iam_instance_profile" "certificate_export_ec2_instance_profile" {
  # name_prefix, not name: instance profile names are account-wide, and the _monolithic template's
  # literal Ec2AdminProfile was shared with three other projects in this repository, so the second
  # of them applied into one account failed on EntityAlreadyExists.
  name_prefix = var.instance_profile_name_prefix
  # A single role name string, not the list CloudFormation's AWS::IAM::InstanceProfile Roles
  # property takes - a profile holds at most one role. The conversion's usual mistake here is
  # jsonencode([...]), which sends the literal string ["terraform-..."] as the role name; the
  # attribute is a string either way, so validate and plan both pass and IAM rejects it during
  # apply (rules.md A-3).
  role = aws_iam_role.certificate_export_ec2_iam_role.name
}
locals {
  # The four objects the bootstrap uploads, keyed by what each one is.
  #
  # Defined once here and consumed in three places: the script below writes them, the output hands
  # the list to the terminator Lambda so it can wait until they have arrived, and the root's
  # download links and credential test scripts name two of them. The names are not free-form - the
  # test scripts download certificate.pem and decrypted_key.pem by exactly these keys - so a second
  # copy of this list somewhere else is a copy that can disagree with the script that produces the
  # files (rules.md B-5).
  exported_object_keys = {
    certificate       = "certificate.pem"
    certificate_chain = "certificate_chain.pem"
    private_key       = "private_key.pem"
    decrypted_key     = "decrypted_key.pem"
  }
  # No set -x, unlike every other EC2 module in this repository, and the _monolithic template did
  # not use it either. cloud-init copies the trace to /var/log/cloud-init-output.log, which any
  # process on the instance can read, and two of the lines below carry the passphrase. set -e is
  # what replaces it for diagnosis: the script stops at the first failure instead of carrying on,
  # so nothing is uploaded, which is what the terminator Lambda's wait notices.
  #
  # Two things about the template syntax below, because both of them break this script silently
  # rather than loudly.
  #
  # The conditional blocks right-trim - if cond ~} and endif ~} - rather than left-trimming with
  # the tilde on the opening brace. A heredoc introduced with <<- strips the common leading
  # indentation from its lines, and a template whose directives left-trim loses that strip
  # entirely: every line arrives with the four spaces it has in this file, the first one included.
  # An indented #! is not a shebang, so cloud-init does not treat the user data as a shell script
  # and runs none of it - no export, and an apply that fails at the terminator Lambda's wait having
  # never executed a command. The right-trimming form keeps the shebang at byte zero and only
  # leaves the conditional body indented, which a shell does not mind (rules.md B-4 for the shape,
  # A-4 for the neighbouring class of bug).
  #
  # And a shell comment inside this heredoc is still template source. The # hides a line from
  # bash, not from Terraform, so a percent sign followed by a brace in a comment opens a directive
  # and fails the parse with "Invalid expression" pointing at the comment. Writing one literally
  # needs it doubled, which is why this explanation lives out here instead.
  user_data = <<-EOT
    #!/bin/bash

    dnf update -yq
    %{if var.install_development_tools~}
    dnf groupinstall -yq "Development Tools"
    %{endif~}
    # jq is not in the Amazon Linux 2023 base image, and the three lines that split export.json
    # below are all jq. The _monolithic template piped to it without installing it, so on an AMI
    # without it every one of those lines fails with "jq: command not found" and - with no set -e
    # there either - the script carried on and uploaded three empty files.
    dnf install -yq jq

    # Strict from here on, and not before: a dnf transaction that decides there is nothing to do
    # is allowed to be unhappy about it, but everything below produces or moves certificate
    # material and a failure in the middle of that must stop the script.
    #
    # This is what keeps a failed export from being published. export-certificate failing leaves
    # export.json holding an error document, jq -e then exits non-zero on the missing field, and
    # the script ends there - before the upload. Without it the four objects would be created
    # holding the four-character string "null", the terminator Lambda would find all four present
    # and terminate, and the demo would hand out a certificate that is not one.
    set -e
    set -o pipefail

    cd /home/ec2-user

    # ACM hands back the certificate, its chain and the private key in one JSON document, with the
    # key encrypted under this passphrase. --passphrase takes a blob, and the AWS CLI v2 default
    # for a blob given on the command line is to base64-decode it, so it is encoded here.
    aws acm export-certificate \
      --certificate-arn "${var.certificate_arn}" \
      --passphrase "$(printf %s "${var.passphrase}" | base64 -w0)" \
      > export.json

    # jq -e, so a field that is absent or null is an error rather than the string "null" written
    # into a file named .pem.
    jq -er '.Certificate' export.json > ${local.exported_object_keys.certificate}
    jq -er '.CertificateChain' export.json > ${local.exported_object_keys.certificate_chain}
    jq -er '.PrivateKey' export.json > ${local.exported_object_keys.private_key}

    # The reason this instance exists. ACM will only export the key encrypted, and the credential
    # helper's --private-key wants PEM it can read without a passphrase, so something has to
    # decrypt it - and nothing in the AWS API will.
    openssl rsa -in ${local.exported_object_keys.private_key} \
      -out ${local.exported_object_keys.decrypted_key} \
      -passin "pass:${var.passphrase}"

    # A loop over the key list rather than four put-object lines, so the files written above and
    # the objects the terminator Lambda waits for cannot drift apart.
    #
    # These uploads are the completion signal. cfn-signal used to follow them, answering a
    # CreationPolicy that no longer exists - the binary is on this AMI, so the call ran and failed
    # with "ValidationError: Stack with id ... does not exist" and left cloud-init reporting
    # status: error for a bootstrap that had done all of its work. The Lambda now waits until all
    # four keys are in the bucket with a timestamp newer than this instance's launch, so the last
    # put-object is what releases the termination.
    for key in ${join(" ", values(local.exported_object_keys))}; do
      aws s3api put-object --bucket ${var.artifact_bucket_name} --key "$key" --body /home/ec2-user/"$key"
    done
    EOT
}
resource "aws_instance" "certificate_export_ec2" {
  ami                         = var.ami_id
  instance_type               = var.instance_type
  subnet_id                   = var.subnet_id
  associate_public_ip_address = var.associate_public_ip_address
  vpc_security_group_ids      = [aws_security_group.certificate_export_ec2_security_group.id]
  iam_instance_profile        = aws_iam_instance_profile.certificate_export_ec2_instance_profile.name
  user_data                   = local.user_data
  tags = {
    Name = var.instance_name
  }
  # Changing user_data stops and starts an instance by default, and cloud-init does not re-run its
  # script on a restart - so an edited bootstrap would never execute. Replacement is what runs it.
  user_data_replace_on_change = true

  # iam_instance_profile orders this after the profile, which orders it after the role - and after
  # neither of the policies on that role. Everything the bootstrap does needs them: exporting the
  # certificate and writing to S3. Losing that race is a bootstrap that fails on
  # AccessDeniedException seconds after a launch that Terraform has already recorded as successful
  # (rules.md D-1).
  depends_on = [
    aws_iam_role_policy.certificate_export_ec2_iam_role,
    aws_iam_role_policy_attachment.certificate_export_ec2_iam_role,
  ]
}
