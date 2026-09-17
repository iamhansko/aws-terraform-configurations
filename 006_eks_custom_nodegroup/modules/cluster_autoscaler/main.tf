# Replaces the _monolithic bootstrap sequence, which ran
#   eksctl create iamserviceaccount --name cluster-autoscaler ...
#   curl -o cluster-autoscaler-autodiscover.yaml ...
#   sed -i "s/<YOUR CLUSTER NAME>/.../g" ...
#   kubectl apply -f cluster-autoscaler-autodiscover.yaml
#   kubectl -n kube-system set image deployment.apps/cluster-autoscaler ...
# from a shell on the bastion (rules.md E-1). That sequence resolved the
# autoscaler image tag at boot time by scraping the GitHub releases API, so two
# applies a month apart silently produced different versions; the chart version
# is pinned here instead.
#
# IAM role and Helm release in one module, since helm_release references the
# role ARN and neither half stands alone (rules.md C-2).
resource "aws_iam_role" "cluster_autoscaler_iam_role" {
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
          "${var.oidc_issuer_host}:sub" = "system:serviceaccount:${var.namespace}:${var.service_account_name}"
          "${var.oidc_issuer_host}:aud" = "sts.amazonaws.com"
        }
      }
    }]
  })
}
# Inline rather than a standalone aws_iam_policy, so it is deleted with the role
# instead of lingering under the account-wide fixed name the _monolithic
# template used ("AmazonEKSClusterAutoscalerPolicy").
resource "aws_iam_role_policy" "cluster_autoscaler_iam_role" {
  role = aws_iam_role.cluster_autoscaler_iam_role.name
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        # Write actions are limited to Auto Scaling groups carrying the opt-in
        # tag that EKS puts on every managed node group's ASG, so the
        # autoscaler cannot resize unrelated groups in the account.
        Effect   = "Allow"
        Action   = ["autoscaling:SetDesiredCapacity", "autoscaling:TerminateInstanceInAutoScalingGroup"]
        Resource = "*"
        Condition = {
          StringEquals = {
            "aws:ResourceTag/k8s.io/cluster-autoscaler/enabled" = "true"
          }
        }
      },
      {
        # Read-only discovery: which ASGs exist, their bounds, and what each
        # instance type provides, so the autoscaler can simulate scale-up.
        Effect = "Allow"
        Action = [
          "autoscaling:DescribeAutoScalingInstances",
          "autoscaling:DescribeAutoScalingGroups",
          "autoscaling:DescribeTags",
          "autoscaling:DescribeLaunchConfigurations",
          "ec2:DescribeLaunchTemplateVersions",
          "ec2:DescribeInstanceTypes",
          "eks:DescribeNodegroup",
        ]
        Resource = "*"
      },
    ]
  })
}
resource "helm_release" "cluster_autoscaler" {
  name       = var.release_name
  repository = var.chart_repository
  chart      = "cluster-autoscaler"
  version    = var.chart_version
  namespace  = var.namespace
  wait       = true
  timeout    = var.timeout_seconds

  set = concat([
    # Auto-discovery finds the node groups' Auto Scaling groups by the
    # k8s.io/cluster-autoscaler/<cluster-name> tag EKS applies to every managed
    # node group, so node groups can be added or removed without touching this
    # release.
    {
      name  = "autoDiscovery.clusterName"
      value = var.cluster_name
    },
    {
      name  = "awsRegion"
      value = var.aws_region
    },
    {
      name  = "rbac.serviceAccount.create"
      value = "true"
    },
    {
      name  = "rbac.serviceAccount.name"
      value = var.service_account_name
    },
    {
      name  = "rbac.serviceAccount.annotations.eks\\.amazonaws\\.com/role-arn"
      value = aws_iam_role.cluster_autoscaler_iam_role.arn
    },
    # The autoscaler's own pod must not be evicted while it is draining a node,
    # otherwise a scale-down can stall halfway. This is the chart equivalent of
    # the "kubectl annotate deployment.apps/cluster-autoscaler
    # cluster-autoscaler.kubernetes.io/safe-to-evict=false" step in the
    # _monolithic userdata.
    #
    # type = "string" is what keeps the "false" a string. Helm's default --set
    # behaviour infers types, so it would reach the chart as a YAML boolean and
    # render an unquoted "safe-to-evict: false" - annotation values must be
    # strings, and the install fails with "Deployment in version v1 cannot be
    # handled as a Deployment: json: cannot unmarshal bool into Go struct field
    # ObjectMeta.spec.template.metadata.annotations of type string". Typed per
    # entry rather than release-wide, because rbac.serviceAccount.create above
    # does have to arrive as a boolean (rules.md E-7).
    {
      name  = "podAnnotations.cluster-autoscaler\\.kubernetes\\.io/safe-to-evict"
      value = "false"
      type  = "string"
    },
    {
      name  = "extraArgs.balance-similar-node-groups"
      value = tostring(var.balance_similar_node_groups)
    },
    {
      name  = "extraArgs.skip-nodes-with-system-pods"
      value = tostring(var.skip_nodes_with_system_pods)
    },
    {
      name  = "extraArgs.scale-down-unneeded-time"
      value = var.scale_down_unneeded_time
    },
    ],
    var.additional_set_values,
  )

  # The role must already carry its inline policy before the autoscaler starts
  # calling Auto Scaling, and referencing the ARN alone doesn't order this
  # release after the policy (rules.md D-1).
  depends_on = [aws_iam_role_policy.cluster_autoscaler_iam_role]
}
