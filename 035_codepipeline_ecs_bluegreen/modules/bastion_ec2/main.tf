# The bastion, which despite the name is a one-shot builder rather than a workbench.
#
# It installs docker, writes a small Go web server and two build files, pushes a seed image to ECR and
# uploads the pipeline's source archive to S3. Then it sits idle. Nothing opens it: there is no
# code-server on it, no SSM association writes a README onto it, and nothing is meant to be read from
# its filesystem - so rules.md H-1's five-tool list and rules.md H-2's README do not apply here. See
# the root outputs.tf for the note that says so where a reader would look for it.
#
# It does keep a key pair and an SSH rule, because the container instance group admits SSH from this
# group, so it is also the hop to a private instance.
resource "aws_security_group" "bastion_security_group" {
  name        = var.security_group_name
  description = var.security_group_description
  vpc_id      = var.vpc_id
  tags = {
    Name = var.security_group_name
  }
}
# Standalone rule resources rather than inline ingress/egress blocks (rules.md F-2), and the egress rule
# below is a fix rather than a transcription.
#
# The _monolithic template's group for this instance declared one inline ingress block for SSH and no
# egress block. In CloudFormation an AWS::EC2::SecurityGroup that names only SecurityGroupIngress keeps
# the allow-all outbound rule EC2 adds at creation; Terraform's inline blocks are attributes-as-blocks
# and authoritative over the whole group, so declaring one revokes that default.
#
# For this instance that is the difference between the project working and producing nothing. Every
# useful line of the userdata goes outbound - dnf install docker, the golang base image from Docker
# Hub, the ECR authorization token, the image push, the S3 upload - so with egress revoked all of them
# fail. And they fail quietly: terraform apply reports success, the instance reaches running, the
# repository and the source bucket stay empty, and the first visible symptom is the ECS service some
# minutes later reporting CannotPullContainerError for an image that was never built, while the
# pipeline's source stage has no object to read. Nothing in that chain points at a security group.
resource "aws_vpc_security_group_egress_rule" "bastion_egress" {
  security_group_id = aws_security_group.bastion_security_group.id
  description       = "All outbound"
  ip_protocol       = "-1"
  cidr_ipv4         = "0.0.0.0/0"
}
# for_each over the CIDR list rather than one resource per source; these are literals in configuration,
# so toset is safe (rules.md B-8).
resource "aws_vpc_security_group_ingress_rule" "bastion_ssh_ingress" {
  for_each = toset(var.ssh_ingress_cidr_blocks)

  security_group_id = aws_security_group.bastion_security_group.id
  description       = "SSH from ${each.value}"
  ip_protocol       = "tcp"
  from_port         = var.ssh_port
  to_port           = var.ssh_port
  cidr_ipv4         = each.value
}
resource "aws_iam_role" "bastion_iam_role" {
  # A generated name, where the _monolithic template used "Ec2AdminRole-${local.stack_suffix}" and
  # needed a random_uuid sliced out of a synthetic CloudFormation stack ARN to make it unique.
  name_prefix = var.role_name_prefix
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
# The _monolithic template attached AdministratorAccess to this role, by name, in Terraform. That is
# rules.md A-5's second case rather than its first - the breadth was not hidden in a shell script
# somewhere outside the template, it was the template's own choice - so narrowing it is a change to
# what the original did and the reason belongs here.
#
# The reason is that A-5's workbench exemption does not reach this instance. The exemption exists
# because a person working inside code-server should not be blocked by IAM partway through a demo. This
# instance is not interactive: its whole job is four calls, all of them in userdata, and the list is
# knowable. Leaving AdministratorAccess on it would be leaving account-wide administrator on an
# instance whose security group admits SSH from the internet and whose key pair's private half sits in
# Parameter Store - which is the worst combination in the project.
#
# So: a policy scoped to exactly those calls, plus AmazonSSMManagedInstanceCore, which is not optional
# here because the completion check in the root is an SSM association that targets this instance.
resource "aws_iam_role_policy" "bastion_build_policy" {
  count = var.create_build_policy ? 1 : 0

  name = "bastion-build"
  role = aws_iam_role.bastion_iam_role.name
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "PushSourceArchive"
        Effect = "Allow"
        # GetObject and ListBucket alongside PutObject because the upload is not the only thing that
        # touches this bucket from here: the completion check in the root runs s3api head-object on the
        # same instance to confirm the archive landed, and head-object is authorized as GetObject.
        Action = ["s3:PutObject", "s3:GetObject", "s3:ListBucket", "s3:GetBucketLocation"]
        Resource = [
          var.source_bucket_arn,
          "${var.source_bucket_arn}/*",
        ]
      },
      {
        Sid    = "AuthenticateToRegistry"
        Effect = "Allow"
        # The one action here that cannot be scoped to a repository. GetAuthorizationToken is an
        # account-level call and IAM rejects a resource other than * for it, so this statement is
        # separate rather than merged with the one below - merging them would silently widen every
        # other action to every repository in the account.
        Action   = ["ecr:GetAuthorizationToken"]
        Resource = "*"
      },
      {
        Sid    = "PushSeedImage"
        Effect = "Allow"
        Action = [
          "ecr:BatchCheckLayerAvailability",
          "ecr:InitiateLayerUpload",
          "ecr:UploadLayerPart",
          "ecr:CompleteLayerUpload",
          "ecr:PutImage",
          "ecr:BatchGetImage",
          "ecr:GetDownloadUrlForLayer",
          # DescribeImages is for the completion check in the root, which asks the repository whether
          # the push actually produced an image rather than trusting the marker file.
          "ecr:DescribeImages",
        ]
        Resource = [var.ecr_repository_arn]
      },
    ]
  })
}
# for_each over the list rather than one attachment per policy (rules.md B-7). toset is safe because
# the ARNs are literal strings in configuration and known at plan time (rules.md B-8).
resource "aws_iam_role_policy_attachment" "bastion_iam_role" {
  for_each   = toset(var.iam_policy_arns)
  role       = aws_iam_role.bastion_iam_role.name
  policy_arn = each.value
}
resource "aws_iam_instance_profile" "bastion_instance_profile" {
  name_prefix = var.instance_profile_name_prefix
  # An instance profile holds at most one role, so this attribute is a single role name string - not the
  # list CloudFormation's AWS::IAM::InstanceProfile Roles property takes. jsonencode([...]) here would
  # send the literal string ["terraform-..."] as roleName, which IAM rejects during apply while
  # terraform validate and plan both pass, because the attribute is a string either way (rules.md A-3).
  role = aws_iam_role.bastion_iam_role.name
}
locals {
  build_directory = "/home/ec2-user/src"

  # Two parsers take a turn at everything below, and knowing which owns which character is what makes
  # this editable safely.
  #
  #  1. Terraform expands ${...} and %{...} and leaves everything else alone. <<-EOT strips the
  #     smallest indentation found across the template's own lines, which here is the four spaces every
  #     line starts with - so the nested heredoc terminators reach the shell at column 0, which is the
  #     only column a shell accepts a terminator at.
  #  2. The instance's shell writes the files. Both nested delimiters are quoted ('TFGOSOURCE',
  #     'TFDOCKERFILE'), so the shell expands nothing inside them - the values are already filled in by
  #     Terraform, and there is no reason for the shell to touch a $ or a backtick.
  #
  # The _monolithic template wrote both files with a single-quoted multi-line echo instead
  # (echo 'package main ... ' > main.go). That works until the content contains an apostrophe, at which
  # point the quote closes early and the rest of the Go program becomes shell. A quoted heredoc has no
  # such edge.
  #
  # set -xe, which is what the original's "#!/bin/bash -xe" shebang asked for, written as a set line
  # because it is the load-bearing part of this script and a flag on the shebang is easy to read past.
  #
  # errexit being on is what makes the missing zip below fatal rather than merely annoying, and it is
  # also what makes the marker file at the end mean something: the marker is written only if every step
  # before it succeeded. The trade-off is in where a failure is reported. A step that fails stops the
  # script before the marker, so the caller's association waits out its timeout and can only say that
  # the script never finished - which is why that message names the log to read. The caller then
  # re-checks ECR and S3 after the marker anyway, because errexit protects against a command that
  # returns non-zero and not against one that succeeds while producing nothing.
  #
  # Everything lands in /var/log/cloud-init-output.log as well as the file below, and that is the first
  # place to look whenever the repository or the source bucket is empty.
  user_data = <<-EOT
    #!/bin/bash
    set -xe
    exec > >(tee /var/log/user-data.log|logger -t user-data -s 2>/dev/console) 2>&1

    dnf update -y
    # zip is the addition here, and it is the single line that decides whether this project does
    # anything at all.
    #
    # The _monolithic template ran "zip src.zip main.go" without installing zip. zip is not in the
    # Amazon Linux 2023 standard AMI - AL2023 ships a far smaller default package set than AL2 did, and
    # the maintainers' answer for the archive tools is that they are in the repository and have to be
    # installed. So the command is not found, which is exit status 127, and with errexit on the script
    # stops there.
    #
    # Everything after that line is therefore everything this instance exists to do. No archive, so no
    # upload and an empty source bucket; no ECR login, no build and no push, so an empty repository.
    # The visible consequences are all somewhere else and none of them mention this instance: the ECS
    # service's tasks stop with CannotPullContainerError against an image that was never built and the
    # service replaces them indefinitely, the pipeline's source stage has no object to read, and
    # because the upload never happened there is no S3 write for CloudTrail to record either - so the
    # EventBridge trigger never fires and the trigger chain looks broken on its own terms.
    #
    # Installing it is a no-op if a future AMI build does include it, so this costs nothing either way.
    dnf install -yq docker zip
    systemctl enable --now docker
    # So that a person who gets onto this box over SSH or Session Manager can run docker without sudo.
    # The build below runs as root and does not need it. This is the form rules.md H-1 asks for, rather
    # than the "chmod 666 /var/run/docker.sock" that several sibling projects use, which hands every
    # local user root-equivalent control of the daemon.
    #
    # The original followed it with "newgrp docker", which is dropped. newgrp is an external command:
    # it changes the group and then execs a shell, and that shell is a child of this script reading
    # commands from stdin - which cloud-init supplies as /dev/null. So it exits immediately having
    # changed nothing about the process that goes on to run the build, and the build did not need the
    # group anyway. It is a no-op here rather than a hang, but only because of what stdin happens to
    # be: run the same script with stdin attached to anything that stays open and it blocks there
    # forever, having installed docker and done nothing else. With errexit on there is a second way for
    # it to matter - a non-zero status from that child shell would end the script - so a line that
    # changes nothing is still a line that can stop everything.
    #
    # There is also no "systemctl restart code-server" after it, which sibling projects need: that
    # restart exists so an already-running IDE picks up the new group, and there is no IDE here.
    usermod -aG docker ec2-user

    mkdir -p ${local.build_directory}
    cd ${local.build_directory}

    cat > main.go << 'TFGOSOURCE'
    package main

    import (
        "fmt"
        "net/http"
    )

    func health(w http.ResponseWriter, req *http.Request) {
        fmt.Fprint(w, "${var.health_response_body}")
    }

    func dummy(w http.ResponseWriter, req *http.Request) {
        fmt.Fprint(w, "${var.dummy_response_body}")
    }

    func main() {
        http.HandleFunc("${var.health_check_path}", health)
        http.HandleFunc("${var.dummy_path}", dummy)
        http.ListenAndServe(":${var.container_port}", nil)
    }
    TFGOSOURCE

    # This Dockerfile is for the seed image only, and it is deliberately not the same as the one the
    # CodeBuild buildspec writes. This one copies the single file it knows is beside it; the
    # buildspec's copies the whole build context, because what it has is the unpacked source archive.
    #
    # No go.mod anywhere, and none is needed: the program imports only the standard library, and
    # "go build main.go" with an explicit file argument resolves stdlib imports without a main module
    # even though module-aware mode has been the default since Go 1.16. "go build ." in the same
    # directory would fail with "go.mod file not found".
    cat > Dockerfile << 'TFDOCKERFILE'
    FROM ${var.go_base_image}
    WORKDIR /app
    COPY main.go .
    RUN go build main.go
    EXPOSE ${var.container_port}
    CMD ["./main"]
    TFDOCKERFILE

    # main.go alone, which looks like an omission and is not - see the Dockerfile the buildspec writes.
    # The archive is the pipeline's source, and the only thing the build needs out of it is the Go
    # file: the buildspec generates its own Dockerfile in pre_build, with COPY . . rather than
    # COPY main.go ., so a Dockerfile shipped in the archive would be overwritten before it was used.
    # Adding it here would therefore change nothing except what a reader expects to find.
    rm -f ${var.source_object_key}
    zip ${var.source_object_key} main.go
    aws s3 cp ${var.source_object_key} s3://${var.source_bucket_name}/${var.source_object_key} --region ${var.region}

    # Login against the registry host with no repository path. docker accepts a login that carries a
    # path and then fails to match it when pushing, which surfaces as "no basic auth credentials" on
    # the push and reads like a permissions problem.
    aws ecr get-login-password --region ${var.region} | docker login --username AWS --password-stdin ${var.ecr_registry_url}
    docker build -t ${var.ecr_image_uri} .
    docker push ${var.ecr_image_uri}

    # The CreationPolicy replacement, and the last thing the script does (rules.md B-4).
    #
    # The original called "/opt/aws/bin/cfn-signal -e $? --stack ... --resource BastionEc2" here, and it
    # could never have worked for two separate reasons: there is no CloudFormation stack for it to
    # signal, and aws-cfn-bootstrap is not installed on Amazon Linux 2023, so the path does not exist
    # and the line ends in "No such file or directory". The conversion's own comment notes that the
    # CreationPolicy it was answering is not reproduced - what the comment does not say is that the
    # wait was load bearing: it is why the task definition and the service came into existence only
    # after an image existed to pull.
    #
    # The marker file is what the caller waits on instead. With errexit on, reaching this line means
    # every step above returned zero - which is close to what the CreationPolicy guaranteed, and the
    # caller still asks ECR and S3 directly, because a command can succeed and produce nothing.
    %{if var.marker_file_path != null~}
    mkdir -p ${var.marker_file_path}
    touch ${var.marker_file_path}/bastion_build
    %{endif~}
    EOT
}
resource "aws_instance" "bastion_ec2" {
  ami                         = var.ami_id
  instance_type               = var.instance_type
  key_name                    = var.key_name
  subnet_id                   = var.subnet_id
  associate_public_ip_address = var.associate_public_ip_address
  vpc_security_group_ids      = [aws_security_group.bastion_security_group.id]
  iam_instance_profile        = aws_iam_instance_profile.bastion_instance_profile.name
  user_data                   = local.user_data
  tags = {
    Name = var.instance_name
  }
  root_block_device {
    # Thirty gigabytes rather than the AMI's eight, which is a divergence from the _monolithic template
    # and the reason is the base image: golang:1.16 is around a gigabyte unpacked, docker keeps the
    # pulled layers as well as the built image, and the built image carries the whole toolchain because
    # the Dockerfile is a single stage. On the eight gigabyte default that fits with very little room,
    # and a build that runs the disk out of space fails in the middle of a layer and - with no set -e -
    # carries on to the push and the marker file regardless.
    volume_type           = var.root_volume_type
    volume_size           = var.root_volume_size
    delete_on_termination = true
  }

  # The instance profile reference orders this after the profile and the role, but not after the policy
  # or the attachment - nothing in this resource refers to either (rules.md D-1). Here that ordering
  # matters more than it usually does: cloud-init starts within seconds of the launch and the
  # userdata's first AWS calls are the S3 upload and "aws ecr get-login-password". Losing that race
  # gives an AccessDenied on both, and with errexit on the script stops there - so the seed image is
  # never pushed and the marker is never written, which the caller reports as a timeout rather than as
  # a permissions problem.
  #
  # The egress rule is in the list for the same reason - a build that starts before outbound exists
  # fails on dnf and never recovers, because nothing retries it.
  depends_on = [
    aws_iam_role_policy.bastion_build_policy,
    aws_iam_role_policy_attachment.bastion_iam_role,
    aws_vpc_security_group_egress_rule.bastion_egress,
  ]
}
# A separate association rather than the instance argument on aws_eip, which is the form the rest of
# this repository uses. The _monolithic template set both associate_public_ip_address on the instance
# and an elastic IP on top of it; keeping both is harmless - the elastic IP replaces the automatically
# assigned address - and the automatic address is what the instance has for the few seconds before this
# resource is created, which is enough for cloud-init to start its first download.
resource "aws_eip" "bastion_elastic_ip" {
  tags = {
    Name = var.instance_name
  }
}
resource "aws_eip_association" "bastion_elastic_ip_association" {
  instance_id   = aws_instance.bastion_ec2.id
  allocation_id = aws_eip.bastion_elastic_ip.id
}
