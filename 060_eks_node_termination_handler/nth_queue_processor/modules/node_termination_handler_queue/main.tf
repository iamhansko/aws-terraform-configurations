# The AWS Node Termination Handler in its queue-processor mode: one Deployment for the whole
# cluster that reads termination events from an SQS queue, rather than a DaemonSet where each
# pod polls its own node's instance metadata.
#
# What the two modes actually differ on:
#
#   IMDS mode   a DaemonSet. Each pod sees only its own instance, and only the events instance
#               metadata carries - spot interruption, rebalance recommendation, scheduled
#               maintenance. It needs no AWS credentials at all.
#   Queue mode  one Deployment. It sees events for every node, including the one no instance
#               can learn about itself: an Auto Scaling group lifecycle hook firing because the
#               group is scaling in or replacing the instance. It also completes that lifecycle
#               action, which is what releases the instance from Terminating:Wait once the
#               drain is done instead of waiting out the heartbeat timeout.
#
# The IRSA role and the release live in one module because the release annotates the service
# account with the role's ARN, so neither is usable without the other (rules.md C-2). The
# queue itself is a separate module: it is plain AWS infrastructure with no Kubernetes side,
# and this module is handed its URL (rules.md B-6).
resource "aws_iam_role" "node_termination_handler_iam_role" {
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
# Split in two so the queue actions can be scoped to the one queue while the describe and
# lifecycle actions, which have no resource-level permissions, stay on "*". The _monolithic
# template put all six actions in a single statement on "*", which meant the handler could read
# and delete messages from every queue in the account.
resource "aws_iam_role_policy" "node_termination_handler_queue_access" {
  name = "queue-access"
  role = aws_iam_role.node_termination_handler_iam_role.name
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "ReadAndDeleteFromThisQueueOnly"
        Effect = "Allow"
        Action = [
          "sqs:ReceiveMessage",
          "sqs:DeleteMessage",
          "sqs:GetQueueAttributes",
          "sqs:GetQueueUrl",
        ]
        Resource = var.queue_arn
      },
      {
        # autoscaling:CompleteLifecycleAction is the one action that distinguishes queue mode:
        # it tells the Auto Scaling group the drain is finished, so the instance leaves
        # Terminating:Wait immediately rather than after the hook's heartbeat expires.
        #
        # None of these four support resource-level permissions, so the resource is "*".
        # DescribeTags and DescribeInstances are what checkTagBeforeDraining reads to decide
        # whether an instance is one it manages.
        Sid    = "InspectInstancesAndCompleteLifecycleActions"
        Effect = "Allow"
        Action = [
          "autoscaling:CompleteLifecycleAction",
          "autoscaling:DescribeAutoScalingInstances",
          "autoscaling:DescribeTags",
          "ec2:DescribeInstances",
        ]
        Resource = "*"
      },
    ]
  })
}
resource "helm_release" "node_termination_handler" {
  name = var.release_name
  # An OCI reference is passed as the chart with no repository argument.
  chart     = var.chart
  version   = var.chart_version
  namespace = var.namespace
  # kube-system already exists, but this keeps the module from depending on that.
  create_namespace = true
  # Holds the apply until the Deployment is available, which is what the _monolithic script's
  # "--wait" did.
  wait    = true
  timeout = var.timeout_seconds

  set = concat([
    {
      # The switch between the two modes. A bare boolean - the chart puts it in an env var
      # through a template that renders whatever it is given, so a quoted "false" would be the
      # non-empty string "false" and read as true by the handler, silently leaving it in IMDS
      # mode with a queue URL it never polls (rules.md E-7).
      name  = "enableSqsTerminationDraining"
      value = "true"
    },
    {
      name  = "queueURL"
      value = var.queue_url
    },
    {
      # Without this the handler falls back to the region from the pod's environment. Setting
      # it explicitly is what the chart's own documentation asks for in queue mode, and it
      # removes one way for the handler to poll a queue URL in a region it is not configured
      # for.
      name  = "awsRegion"
      value = var.aws_region
    },
    {
      name  = "serviceAccount.create"
      value = "true"
    },
    {
      name  = "serviceAccount.name"
      value = var.service_account_name
    },
    {
      name  = "serviceAccount.annotations.eks\\.amazonaws\\.com/role-arn"
      value = aws_iam_role.node_termination_handler_iam_role.arn
    },
    {
      name  = "replicas"
      value = tostring(var.replica_count)
    },
    {
      # Defaults to true in the chart, so it is set explicitly rather than relied on: with it
      # on, the handler ignores any instance not carrying managed_tag, and an untagged node
      # group is therefore never drained. That failure is completely silent - the notice
      # arrives, the handler decides the instance is not its business, and the node disappears
      # with no drain and no error.
      name  = "checkTagBeforeDraining"
      value = tostring(var.check_tag_before_draining)
    },
    {
      name  = "managedTag"
      value = var.managed_tag
      # A tag key, so it has to stay a string. Without this a key that happened to look
      # numeric would reach the chart as a number (rules.md E-7).
      type = "string"
    },
    {
      # How long a pod gets after the eviction is issued, before the handler stops waiting.
      # Has to fit inside the two minutes a spot interruption gives, which is why the chart's
      # default of 120 is the ceiling rather than a target.
      name  = "nodeTerminationGracePeriod"
      value = tostring(var.node_termination_grace_period)
    },
    {
      # Taints the node in addition to cordoning it, so pods that tolerate an unschedulable
      # node are still moved. Off in the chart by default; on here because the demo's point is
      # that the workload leaves the node.
      name  = "taintNode"
      value = tostring(var.taint_node)
    },
    {
      # Records the drain as Kubernetes events on the node, which is what makes the handler's
      # decisions visible to kubectl rather than only in its own log.
      name  = "emitKubernetesEvents"
      value = tostring(var.emit_kubernetes_events)
    },
    ],
    var.additional_set_values,
  )

  # The role must already carry its policy before the handler's first poll, and the service
  # account annotation referencing the role's ARN does not order this after the policy
  # (rules.md D-1). A handler that starts without the policy logs an AccessDenied on
  # ReceiveMessage and keeps retrying, so the failure is recoverable but noisy.
  depends_on = [aws_iam_role_policy.node_termination_handler_queue_access]
}
