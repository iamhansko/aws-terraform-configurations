data "aws_ssm_parameter" "eks_optimized_ami_id" {
  name = var.ami_ssm_parameter_name
}

# A self-managed worker node: a plain EC2 instance that joins the cluster because its user
# data tells it how, rather than a member of an EKS managed node group.
#
# That is the subject of this variant, and what it costs is worth naming: EKS knows nothing
# about this instance. Nothing drains it before termination, nothing replaces it when the AMI
# moves, and nothing notices if it never joins - the instance reaches "running" either way and
# the failure is only visible as a node missing from kubectl get nodes.
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

# The access entry is what makes this instance's role a Kubernetes node identity. Without it
# the kubelet authenticates and is refused, so the instance boots, joins nothing, and reports
# no error anywhere the AWS console would show it.
#
# Type EC2_LINUX, not STANDARD: it maps the role into system:nodes rather than to a user, and
# EKS supplies the RBAC a kubelet needs. It lives in this module rather than in the root
# because the role it names is created here and is useful for nothing else - unlike the
# workbench's access entry, which joins two independent modules (rules.md C-1/C-2).
resource "aws_eks_access_entry" "node" {
  cluster_name  = var.cluster_name
  principal_arn = aws_iam_role.node.arn
  type          = "EC2_LINUX"
}

locals {
  # The NodeConfig document nodeadm reads out of user data on an AL2023 EKS-optimized AMI.
  # Built as an HCL object and rendered with yamlencode rather than written as YAML text, so
  # the endpoint, the certificate, the service CIDR and the DNS address are typed values from
  # the cluster module (rules.md E-3). The _monolithic template wrote this as literal YAML
  # with the CIDR and clusterDNS hardcoded to 172.20.0.0/16 and 172.20.0.10 - correct only as
  # long as nobody changed the cluster's service CIDR, and silently wrong if they did.
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
  # content types and both have to travel in one user data field.
  #
  # The boundary is a literal, and the trailing "--" on the last one is what closes the
  # document. A missing closing boundary leaves the last part unterminated and nodeadm ignores
  # it, which reads as a node that joined with default kubelet settings.
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

resource "aws_instance" "node" {
  ami                         = data.aws_ssm_parameter.eks_optimized_ami_id.insecure_value
  instance_type               = var.instance_type
  key_name                    = var.key_name
  subnet_id                   = var.subnet_id
  associate_public_ip_address = false
  vpc_security_group_ids      = var.vpc_security_group_ids
  iam_instance_profile        = aws_iam_instance_profile.node.name
  user_data                   = local.user_data

  root_block_device {
    volume_size = var.root_volume_size
    volume_type = "gp3"
    encrypted   = true
  }

  metadata_options {
    http_endpoint = "enabled"
    http_tokens   = "required"
    # Two, not one. The kubelet and the CNI run in the host network namespace and would be
    # fine with one, but a pod that reads instance metadata needs the extra hop - and with
    # ENABLE_MULTI_NIC on, the CNI's own probing does too.
    http_put_response_hop_limit = var.instance_metadata_http_put_response_hop_limit
  }

  tags = {
    Name = var.name
  }

  # Three things have to be true before this instance can join, and none of them is implied by
  # a value reference: the role has to carry its policies, the access entry has to exist, and
  # IAM has to have propagated the instance profile. A node that boots first authenticates and
  # is refused, then retries - so the failure is a node that appears minutes late, or not at
  # all (rules.md D-1).
  depends_on = [
    aws_iam_role_policy_attachment.node,
    aws_eks_access_entry.node,
  ]
}
