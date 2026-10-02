# Cilium as the cluster's CNI and as its kube-proxy.
#
# The _monolithic template installed this with a helm command in the bastion's userdata.
# Two things went wrong there and neither reported itself. The helm command sat after an
# "exec bash" line, which replaces the running shell, so it - and the cilium CLI install
# after it - never ran at all (rules.md E-1/H-1). And the cluster left
# bootstrap_self_managed_addons at its default of true, so EKS installed vpc-cni and
# kube-proxy anyway: the nodes came up Ready on the VPC CNI, every pod got an address,
# and a project about replacing both shipped with both in place and Cilium absent.
#
# The cluster module here sets bootstrap_self_managed_addons = false and this root
# installs no vpc-cni or kube-proxy addon, which is what makes this release load-bearing
# rather than decorative.
#
# The IAM role and the chart are one module because the chart annotates the service
# account with the role's ARN, and neither half does anything alone (rules.md C-2).
resource "aws_iam_role" "cilium_operator_iam_role" {
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = {
        Federated = var.oidc_provider_arn
      }
      Action = "sts:AssumeRoleWithWebIdentity"
      Condition = {
        StringEquals = {
          "${var.oidc_issuer_host}:sub" = "system:serviceaccount:${var.namespace}:${var.operator_service_account_name}"
          "${var.oidc_issuer_host}:aud" = "sts.amazonaws.com"
        }
      }
    }]
  })
}
# IRSA rather than the node instance role, which is where the _monolithic template would
# have left it: the operator would have picked up the node role through IMDS, and so
# would every other pod on that node. This scopes the ENI permissions to one service
# account.
#
# The set of actions matters. AmazonEKS_CNI_Policy - which the node role already carries
# and which is what the VPC CNI needs - is not sufficient for Cilium in ENI mode: it has
# no ec2:DescribeVpcs and no ec2:DescribeSecurityGroups, both of which the operator calls
# while building its view of the VPC before it allocates anything. Missing them does not
# produce a permissions error anywhere a user would look; the operator logs an
# UnauthorizedOperation and pods simply stay without addresses.
resource "aws_iam_role_policy" "cilium_operator_iam_role" {
  role = aws_iam_role.cilium_operator_iam_role.name
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          # Read: how the operator learns which subnets, security groups and instance
          # types it is working with.
          "ec2:DescribeNetworkInterfaces",
          "ec2:DescribeInstances",
          "ec2:DescribeInstanceTypes",
          "ec2:DescribeSubnets",
          "ec2:DescribeVpcs",
          "ec2:DescribeSecurityGroups",
          "ec2:DescribeTags",
          # DescribeRouteTables was missing from this list and it is not optional: the operator
          # reads route tables while building its view of the VPC, during the initial
          # synchronisation that has to finish before it allocates anything. Without it:
          #
          #   UnauthorizedOperation: ... not authorized to perform: ec2:DescribeRouteTables
          #   level=fatal "Unable to start eni allocator"
          #     error="Initial synchronization with instances API failed"
          #
          # which leaves the operator in CrashLoopBackOff, the agents with zero allocatable
          # addresses, and every pod that needs one - starting with coredns - in
          # ContainerCreating. The coredns addon then fails with InsufficientNumberOfReplicas,
          # and that is the only error Terraform ever shows.
          "ec2:DescribeRouteTables",
          # Write: attaching interfaces to instances and moving addresses onto them,
          # which is the allocation itself.
          "ec2:CreateNetworkInterface",
          "ec2:DeleteNetworkInterface",
          "ec2:AttachNetworkInterface",
          "ec2:DetachNetworkInterface",
          "ec2:ModifyNetworkInterfaceAttribute",
          "ec2:AssignPrivateIpAddresses",
          "ec2:UnassignPrivateIpAddresses",
          "ec2:CreateTags",
        ]
        Resource = "*"
      },
    ]
  })
}
locals {
  # YAML rather than set entries. kubeProxyReplacement is a real boolean in this chart,
  # and helm's set would infer one correctly - but the annotation below must stay a
  # string, and mixing the two in one set list means remembering which entries need
  # type = "string" (rules.md E-7). yamlencode keeps every type as written.
  values = merge(
    {
      # ENI mode: the operator attaches interfaces and hands out VPC addresses, so pods
      # are routable from an AWS load balancer with target-type ip.
      eni = {
        enabled = var.ipam_mode == "eni"
      }
      ipam = {
        mode = var.ipam_mode
      }
      routingMode = var.routing_mode
      # No kube-proxy exists on this cluster, so this is not an optimisation - it is the
      # only thing implementing Services.
      kubeProxyReplacement = var.kube_proxy_replacement
      # Reached directly rather than through the in-cluster kubernetes Service, which
      # nothing would translate until Cilium is already running.
      k8sServiceHost = var.k8s_service_host
      k8sServicePort = var.k8s_service_port
      operator = {
        replicas = var.operator_replicas
        # AWS_REGION, because nothing else gives the operator one and in ENI mode every EC2
        # call needs it.
        #
        # IRSA normally covers this: the EKS pod identity webhook injects AWS_ROLE_ARN, the
        # token file, AWS_REGION and AWS_DEFAULT_REGION. It skips any variable the pod already
        # declares, and this chart declares AWS_DEFAULT_REGION itself - as an optional
        # secretKeyRef on a "cilium-aws" secret that does not exist here. So the webhook leaves
        # the region alone, the optional reference resolves to nothing, and the operator starts
        # with credentials but no region. Measured on the running pod: AWS_ROLE_ARN and
        # AWS_WEB_IDENTITY_TOKEN_FILE present, AWS_REGION absent.
        #
        # What that looked like was not a region error. The failing call is wrapped in a poll
        # loop, so the operator reported only the loop's timeout:
        #
        #   level=error subsys=aws-eni-limits "Failed initial EC2 API limits update"
        #     error="timed out waiting for the condition"
        #   level=fatal "Unable to start eni allocator"
        #
        # which reads like a network or permissions problem and is neither. A probe pod with the
        # same service account, which does not declare AWS_DEFAULT_REGION and therefore did get a
        # region, called sts:GetCallerIdentity and ec2:DescribeInstanceTypes successfully.
        #
        # AWS_REGION rather than AWS_DEFAULT_REGION: the chart already has an entry of that name,
        # and extraEnv appends rather than replaces, so setting it here would leave two entries
        # with one name. The SDK reads AWS_REGION first anyway.
        extraEnv = [
          {
            name  = "AWS_REGION"
            value = var.region
          },
        ]
      }
      serviceAccounts = {
        operator = {
          name = var.operator_service_account_name
          annotations = {
            # A string, and Kubernetes requires annotation values to be strings. An
            # inferred type here is rejected when the object is decoded (rules.md E-7).
            "eks.amazonaws.com/role-arn" = aws_iam_role.cilium_operator_iam_role.arn
          }
        }
      }
    },
    var.egress_masquerade_interfaces == null ? {} : {
      egressMasqueradeInterfaces = var.egress_masquerade_interfaces
    },
  )
}
resource "helm_release" "cilium" {
  name       = var.release_name
  repository = var.chart_repository
  chart      = "cilium"
  version    = var.chart_version
  namespace  = var.namespace

  # False by default, and this is the one release in the repository where that is
  # correct. See var.wait_for_release: there are no nodes yet when this runs, by
  # necessity, so nothing can become ready.
  wait    = var.wait_for_release
  timeout = var.timeout_seconds

  values = [yamlencode(local.values)]

  # The operator cannot assume the role until the role carries its policy, and
  # referencing the role's ARN alone does not order this after the policy
  # (rules.md D-1).
  depends_on = [aws_iam_role_policy.cilium_operator_iam_role]
}
