data "aws_region" "current" {}
resource "aws_security_group" "image_builder_security_group" {
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
# The _monolithic template's security group for this instance declared no ingress and no egress at all -
# just a name, a description and a VPC. In CloudFormation that is a group with the allow-all egress rule
# AWS adds at creation still in place, because AWS::EC2::SecurityGroup only takes over the rules a
# template actually names. Terraform's inline ingress/egress are attributes-as-blocks and authoritative
# over the whole group, so omitting them does not inherit that default: the provider revokes it, and the
# group ends up with no outbound access whatsoever.
#
# For this instance that is the difference between the project working and producing nothing. Every
# useful line of the userdata goes outbound - dnf install docker, the amazoncorretto base image from
# Docker Hub, the ECR authorization token, the push - so with egress revoked all of them fail. And they
# fail quietly: terraform apply reports success, the instance reaches "running", the repository stays
# empty, and the first visible symptom is the ECS service some minutes later reporting
# CannotPullContainerError against an image that was never built. Nothing in that chain points back at a
# security group.
#
# Standalone rules make each direction a resource that is visibly present or visibly absent in a plan,
# which is the shape that would have made this obvious.
resource "aws_vpc_security_group_egress_rule" "image_builder_egress" {
  security_group_id = aws_security_group.image_builder_security_group.id
  description       = "All outbound"
  ip_protocol       = "-1"
  cidr_ipv4         = "0.0.0.0/0"
}
# No ingress by default, which is what the original had. for_each over the CIDR list rather than one
# resource per source; the values are literals in configuration, so toset is safe here (rules.md B-8).
resource "aws_vpc_security_group_ingress_rule" "image_builder_ssh_ingress" {
  for_each = toset(var.ssh_ingress_cidr_blocks)

  security_group_id = aws_security_group.image_builder_security_group.id
  description       = "SSH from ${each.value}"
  ip_protocol       = "tcp"
  from_port         = 22
  to_port           = 22
  cidr_ipv4         = each.value
}
resource "aws_iam_role" "image_builder_iam_role" {
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
# for_each over the policy list rather than one attachment resource per policy, so a caller can add or
# remove a policy without the module changing (rules.md B-7). toset is safe because the ARNs are literal
# strings in configuration and are therefore known at plan time (rules.md B-8).
resource "aws_iam_role_policy_attachment" "image_builder_iam_role" {
  for_each   = toset(var.iam_policy_arns)
  role       = aws_iam_role.image_builder_iam_role.name
  policy_arn = each.value
}
resource "aws_iam_instance_profile" "image_builder_instance_profile" {
  # An instance profile holds at most one role, so this attribute is a single role name string - not the
  # list CloudFormation's AWS::IAM::InstanceProfile Roles property takes. jsonencode([...]) here would
  # send the literal string ["terraform-..."] as roleName, which IAM rejects during apply while terraform
  # validate and plan both pass, because the attribute is a string either way (rules.md A-3).
  role = aws_iam_role.image_builder_iam_role.name
}
locals {
  # The build context directory. The _monolithic template wrote the Dockerfile into /home/ec2-user and
  # ran "docker build ." there, which hands the whole home directory to the daemon as the build context.
  # It is nearly empty on a fresh instance so it worked, but a dedicated directory makes the context one
  # file and keeps it that way.
  build_directory = "/home/ec2-user/image"

  # Three parsers take a turn at the Dockerfile below, and knowing which one owns which character is the
  # difference between editing it safely and quietly breaking the container.
  #
  #  1. Terraform expands ${...} and %{...} and leaves everything else alone. Heredocs do not interpret
  #     backslash escapes, so every \n and every trailing \ in here reaches the instance literally.
  #  2. The instance's shell writes the file. The heredoc delimiter is quoted ('TFDOCKERFILE'), so the
  #     shell expands nothing - which is what keeps $counter, $(ls ...) and $((counter + 1)) alive for
  #     the container to evaluate at runtime instead of being resolved to empty strings on the builder.
  #     The original wrote the delimiter as $'EOF'; ANSI-C quoting collapses that to EOF and, being
  #     quoted, suppresses expansion in the same way, so it worked - but it reads as though an expansion
  #     is wanted when the opposite is the load-bearing part, so the delimiter is plainly quoted here.
  #  3. Docker's parser joins the backslash-newline continuations in the RUN line into one long command
  #     before any shell sees it, and then bash's $'...' turns each \n into a real newline. This step is
  #     the one that cannot be rehearsed outside a Dockerfile: feed the same text to a shell directly and
  #     the backslashes survive as literals, because $'...' does not treat backslash-newline as a
  #     continuation.
  #
  # findutils in place of the original's coreutils, and both halves of that change are load-bearing.
  #
  #   - coreutils fails the build. amazoncorretto:21 is built on Amazon Linux 2023 with coreutils-single
  #     already installed, and the two packages conflict, so yum refuses ("package coreutils ... conflicts
  #     with coreutils-single provided by coreutils-single-8.32-30.amzn2023.0.5") and the RUN step exits
  #     1. Nothing is pushed. coreutils-single is the same coreutils in one binary, so dd, du, sync, ls,
  #     tail, wc, rm, mkdir and sleep are all already there - the line was asking for nothing it lacked.
  #   - findutils is what the test script was missing. The cleanup step pipes into xargs, and the base
  #     image has no xargs. Without it the container still runs and still writes, but every cleanup prints
  #     "xargs: command not found", no file is ever deleted, and the host volume fills until dd fails.
  #
  # Checked against amazoncorretto:21 on Amazon Linux 2023.12 by running the same yum line in a throwaway
  # container on this instance type, then resolving every command the script calls.
  #
  # set -x and no set -e, as the original had it. Everything lands in
  # /var/log/cloud-init-output.log, which is the first place to look when the repository is empty.
  #
  # Not adding set -e is a decision rather than something inherited. With it, a failed docker login would
  # stop the script before the marker file and the caller's association would then sit until its timeout
  # with nothing to say beyond "it never finished". Without it the script always reaches the marker, the
  # caller's ECR check is what decides whether the build actually produced anything, and that failure
  # names the repository. The cost is that the marker means "the script ran to the end" and nothing more,
  # which is exactly why the caller does not trust it on its own.
  user_data = <<-EOT
    #!/bin/bash
    set -x

    dnf install -yq docker
    dnf install -yq bash-completion
    systemctl enable --now docker
    # So that a person who gets onto this box over Session Manager can run docker without sudo. The build
    # below runs as root and does not need it.
    #
    # The original followed this with "newgrp docker", which is dropped. newgrp is an external command: it
    # execs a new shell as a child of this script, and that shell reads its commands from stdin - which
    # cloud-init supplies as /dev/null. So it returns immediately having changed nothing about the process
    # that goes on to run the build, and the build did not need the group anyway.
    usermod -aG docker ec2-user

    mkdir -p ${local.build_directory}
    cd ${local.build_directory}

    cat > Dockerfile << 'TFDOCKERFILE'
    FROM ${var.java_base_image}
    RUN yum update -y && \
        yum install -y procps util-linux findutils && \
        yum clean all
    WORKDIR /app
    RUN echo $'#!/bin/bash \n\
    echo "Starting test" \n\
    mkdir -p ${var.container_mount_path} \n\
    counter=0 \n\
    while true; do \n\
      echo "[$counter] Writing ${var.write_size_mb}MB file with direct I/O" \n\
      dd if=/dev/zero of=${var.container_mount_path}/test_$counter.dat bs=1M count=${var.write_size_mb} oflag=direct 2>&1 | tail -1 \n\
      sync \n\
      echo "[$counter] Current disk usage : " \n\
      du -sh ${var.container_mount_path} \n\
      file_count=$(ls -1 ${var.container_mount_path} 2>/dev/null | wc -l) \n\
      if [ $file_count -gt ${var.retained_file_count} ]; then \n\
        echo "Cleaning up old files" \n\
        ls -t ${var.container_mount_path}/* | tail -n +${var.retained_file_count + 1} | xargs rm -f \n\
        sync \n\
      fi \n\
      counter=$((counter + 1)) \n\
      sleep 1 \n\
    done' > /app/test.sh
    RUN chmod +x /app/test.sh
    CMD ["/bin/bash", "/app/test.sh"]
    TFDOCKERFILE

    # Login against the registry host with no repository path. docker accepts a login that carries a path
    # and then fails to match it when pushing, which surfaces as "no basic auth credentials" on the push
    # and reads like a permissions problem.
    aws ecr get-login-password --region ${data.aws_region.current.region} | docker login --username AWS --password-stdin ${var.ecr_registry_url}
    # No --platform: this instance is arm64 and so are the container instances that will pull the result.
    # See the instance_type variable for what building this anywhere else produces.
    docker build -t ${var.ecr_image_uri} .
    docker push ${var.ecr_image_uri}

    # The CreationPolicy replacement, and the last thing the script does (rules.md B-4).
    #
    # The original called "/opt/aws/bin/cfn-signal -e $? --stack ... --resource Ec2" here. Two separate
    # reasons that could never have worked: there is no CloudFormation stack for it to signal, and
    # aws-cfn-bootstrap is not installed on Amazon Linux 2023, so the path does not exist and the line
    # ends in "No such file or directory". The marker file is what the caller waits on instead.
    %{if var.marker_file_path != null~}
    mkdir -p ${var.marker_file_path}
    touch ${var.marker_file_path}/image_builder
    %{endif~}
    EOT
}
resource "aws_instance" "image_builder_ec2" {
  ami                         = var.ami_id
  instance_type               = var.instance_type
  key_name                    = var.key_name
  subnet_id                   = var.subnet_id
  associate_public_ip_address = var.associate_public_ip_address
  vpc_security_group_ids      = [aws_security_group.image_builder_security_group.id]
  iam_instance_profile        = aws_iam_instance_profile.image_builder_instance_profile.name
  user_data                   = local.user_data
  # The userdata is this instance's whole job, and cloud-init runs it once, on the first boot. Without
  # this, a change to the Dockerfile or to any variable rendered into it - the base image, the write
  # size, the mount path - is applied in place: the provider stops the instance, swaps the userdata and
  # starts it again, cloud-init skips it as already run, and the repository keeps the old image (or, after
  # a failed build, none) while the plan reported the change as made. Replacing the instance is what
  # actually rebuilds, and the caller's verification association follows the new instance id, so it
  # re-runs against it.
  user_data_replace_on_change = true
  tags = {
    Name = var.instance_name
  }
  root_block_device {
    volume_type           = var.root_volume_type
    volume_size           = var.root_volume_size
    delete_on_termination = true
  }

  # The instance profile reference orders this after the profile and the role, but not after the policy
  # attachment - nothing in this resource refers to it (rules.md D-1). Here that ordering matters more
  # than it usually does: cloud-init starts within seconds of the launch and the userdata's first AWS
  # call is "aws ecr get-login-password". Losing that race gives an AccessDenied on the token, the push
  # never happens, and the script carries on to the marker file regardless.
  depends_on = [aws_iam_role_policy_attachment.image_builder_iam_role]
}
