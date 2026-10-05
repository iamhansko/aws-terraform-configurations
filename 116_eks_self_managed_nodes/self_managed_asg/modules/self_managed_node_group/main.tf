data "aws_ssm_parameter" "eks_optimized_ami_id" {
  name = var.ami_ssm_parameter_name
}

# A self-managed node group: a launch template and an Auto Scaling group, whose instances join
# the cluster because their user data tells them how.
#
# The difference from the self_managed_node variant is what the ASG adds and what it does not.
# It replaces a failed instance and it can hold more than one, so the capacity survives an
# instance dying - but EKS still knows nothing about any of it. Nothing drains a node the ASG
# is about to terminate, so a scale-in or an instance refresh kills pods rather than evicting
# them. A managed node group is what adds that; this is the layer below it.
resource "aws_iam_role" "node" {
  name_prefix = "${substr(var.name, 0, 32)}-"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "ec2.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy_attachment" "node" {
  for_each   = toset(var.node_iam_policy_arns)
  role       = aws_iam_role.node.name
  policy_arn = each.value
}

# role, not jsonencode([role]). An instance profile holds at most one role, so the provider
# takes a single name string - the _monolithic template carried jsonencode([...]) here, a
# straight transcription of CloudFormation's Roles list, which fails at apply with an IAM API
# error (rules.md A-3).
resource "aws_iam_instance_profile" "node" {
  name_prefix = "${substr(var.name, 0, 32)}-"
  role        = aws_iam_role.node.name
}

# The access entry is what makes the instances' role a Kubernetes node identity. Without it
# every kubelet authenticates and is refused, so the ASG reports a healthy group of instances
# that joined nothing.
#
# Type EC2_LINUX, not STANDARD: it maps the role into system:nodes rather than to a user, and
# EKS supplies the RBAC a kubelet needs.
resource "aws_eks_access_entry" "node" {
  cluster_name  = var.cluster_name
  principal_arn = aws_iam_role.node.arn
  type          = "EC2_LINUX"
}

locals {
  # The NodeConfig document nodeadm reads out of user data on an AL2023 EKS-optimized AMI. Built
  # as an HCL object and rendered with yamlencode rather than written as YAML text, so the
  # endpoint, the certificate, the service CIDR and the DNS address are typed values from the
  # cluster module (rules.md E-3). The _monolithic template wrote it as literal YAML with the
  # CIDR and clusterDNS hardcoded to 172.20.0.0/16 and 172.20.0.10.
  node_config = {
    apiVersion = "node.eks.aws/v1alpha1"
    kind       = "NodeConfig"
    spec = {
      cluster = {
        name                 = var.cluster_name
        apiServerEndpoint    = var.cluster_endpoint
        certificateAuthority = var.certificate_authority_data
        cidr                 = var.service_ipv4_cidr
      }
      kubelet = {
        config = {
          maxPods    = var.max_pods
          clusterDNS = [var.cluster_dns_ip]
        }
      }
    }
  }

  # A MIME multipart document, because nodeadm's config and a shell script are two different
  # content types and both have to travel in one user data field. The trailing "--" on the last
  # boundary is what closes the document; without it the last part is unterminated and nodeadm
  # ignores it, which reads as nodes that joined with default kubelet settings.
  user_data = <<-EOT
    MIME-Version: 1.0
    Content-Type: multipart/mixed; boundary="==BOUNDARY=="

    --==BOUNDARY==
    Content-Type: application/node.eks.aws

    ---
    ${yamlencode(local.node_config)}
    --==BOUNDARY==
    Content-Type: text/x-shellscript; charset="us-ascii"

    #!/bin/bash
    ${var.additional_user_data}
    --==BOUNDARY==--
  EOT
}

resource "aws_launch_template" "node" {
  # name_prefix, not a fixed name. A launch template name has to be unique in the account, so a
  # fixed one makes a second copy of this project collide - and any change that replaces the
  # template has to delete the old one first, which the ASG referencing it prevents. The
  # _monolithic template hardcoded "eks-node-lt".
  name_prefix            = "${var.name}-"
  image_id               = data.aws_ssm_parameter.eks_optimized_ami_id.insecure_value
  instance_type          = var.instance_type
  key_name               = var.key_name
  vpc_security_group_ids = var.vpc_security_group_ids
  user_data              = base64encode(local.user_data)

  iam_instance_profile {
    name = aws_iam_instance_profile.node.name
  }

  block_device_mappings {
    device_name = "/dev/xvda"
    ebs {
      volume_size = var.root_volume_size
      volume_type = "gp3"
      encrypted   = true
      # Without this the volume survives the instance, which on an ASG that replaces instances
      # means an orphaned volume per replacement - billed, and attached to nothing.
      delete_on_termination = true
    }
  }

  metadata_options {
    http_endpoint = "enabled"
    http_tokens   = "required"
    # Two, not one, so a pod that reads instance metadata can reach it - and with
    # ENABLE_MULTI_NIC on, the CNI's own probing needs it too.
    http_put_response_hop_limit = var.instance_metadata_http_put_response_hop_limit
  }

  tag_specifications {
    resource_type = "instance"
    tags = {
      Name = var.name
    }
  }

  # The volumes as well as the instances. The _monolithic template tagged only instances, so the
  # root volumes had no Name at all.
  tag_specifications {
    resource_type = "volume"
    tags = {
      Name = var.name
    }
  }
}

resource "aws_autoscaling_group" "node" {
  name_prefix         = "${var.name}-"
  min_size            = var.min_size
  max_size            = var.max_size
  desired_capacity    = var.desired_capacity
  default_cooldown    = var.default_cooldown
  vpc_zone_identifier = var.subnet_ids
  # EC2 health checks only. An ELB health check would be wrong here - nothing registers these
  # instances with a load balancer, so the ASG would have nothing to ask.
  health_check_type = "EC2"
  # How long a new instance is given before its health check counts. nodeadm has to run, the
  # kubelet has to start and the CNI image has to pull; a shorter grace period makes the ASG
  # terminate instances that were still booting, which looks like an instance that keeps
  # replacing itself.
  health_check_grace_period = var.health_check_grace_period

  launch_template {
    id      = aws_launch_template.node.id
    version = aws_launch_template.node.latest_version
  }

  # The tag the cluster autoscaler and Karpenter both look for on a self-managed group. Neither
  # is installed here, but the tag is what makes this group discoverable if one is added - and
  # it is free. The _monolithic template used a mixed_instances_policy with a single launch
  # template and no overrides, which is the same thing as a plain launch_template block with
  # more configuration around it.
  tag {
    key                 = "kubernetes.io/cluster/${var.cluster_name}"
    value               = "owned"
    propagate_at_launch = true
  }

  instance_refresh {
    strategy = "Rolling"
    preferences {
      min_healthy_percentage = var.refresh_min_healthy_percentage
    }
  }

  lifecycle {
    # The desired capacity moves for reasons outside this configuration - a scaling policy, a
    # person, or an autoscaler if one is added later. Ignoring it keeps every subsequent plan
    # from proposing to put it back (rules.md E-8 makes the same argument about a Deployment's
    # replicas, which is exactly the same problem one layer up).
    ignore_changes = [desired_capacity]
  }

  # The role has to carry its policies and the access entry has to exist before an instance
  # boots, and neither is implied by a value reference. An instance that boots first
  # authenticates, is refused, and retries - so the failure is a node that appears minutes late
  # or not at all (rules.md D-1).
  depends_on = [
    aws_iam_role_policy_attachment.node,
    aws_eks_access_entry.node,
  ]
}
