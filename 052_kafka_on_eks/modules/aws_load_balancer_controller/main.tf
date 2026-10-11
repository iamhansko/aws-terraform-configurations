# Replaces 052's post-install SSM association, which ran
#   aws iam create-policy --policy-document file://iam_policy.json
#   eksctl create iamserviceaccount --name aws-load-balancer-controller ...
#   helm upgrade --install aws-load-balancer-controller eks/aws-load-balancer-controller
# from a shell on the workbench (rules.md E-1). eksctl's iamserviceaccount step
# built a CloudFormation stack Terraform knew nothing about, and the chart had no
# --version; here the IRSA role is a resource in state and the chart is pinned.
#
# The IAM role and the Helm release stay in one module because helm_release
# references the role ARN directly and neither half is useful alone
# (rules.md C-2). The cross-module rule about injecting ARNs through variables
# (rules.md C-1/B-6) applies between modules with different responsibilities,
# not within a single component.
resource "aws_iam_role" "aws_load_balancer_controller_iam_role" {
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
# The controller's upstream least-privilege policy, vendored from
# kubernetes-sigs/aws-load-balancer-controller v2.14.1 docs/install/iam_policy.json - v2.14.1 being
# the app version of chart 1.14.1, because the policy and the controller have to come from the same
# release or the controller asks for permissions the policy does not grant.
#
# This is what 052 ran before: its post-install step downloaded the same document (at v2.13.4) and
# created it as a managed policy. The copies of this module elsewhere in the repository carry
# "ec2:*" and "elasticloadbalancing:*" on every resource instead, from their own _monolithic
# templates; taking that copy here would have widened what this project's controller could do
# (rules.md A-5).
#
# Inline rather than a standalone aws_iam_policy, so the permissions are deleted with the role and a
# second copy of this project cannot collide on a policy name. jsondecode/jsonencode strips the file's
# whitespace, which IAM would otherwise count against the policy size limit.
resource "aws_iam_role_policy" "aws_load_balancer_controller_iam_role" {
  role   = aws_iam_role.aws_load_balancer_controller_iam_role.name
  policy = jsonencode(jsondecode(file("${path.module}/iam_policy.json")))
}
resource "helm_release" "aws_load_balancer_controller" {
  name       = var.release_name
  repository = var.chart_repository
  chart      = "aws-load-balancer-controller"
  version    = var.chart_version
  namespace  = var.namespace
  # wait = true makes the apply block until the controller's Deployment is
  # Available, which is what the post-install step's helm --wait was for - and
  # the controller's Ingress webhooks reject every Ingress until it is.
  wait    = true
  timeout = var.timeout_seconds

  set = concat([
    {
      name  = "clusterName"
      value = var.cluster_name
    },
    {
      name  = "region"
      value = var.aws_region
    },
    {
      name  = "vpcId"
      value = var.vpc_id
    },
    {
      name  = "replicaCount"
      value = tostring(var.replica_count)
    },
    # The chart creates the service account itself and only needs the IRSA
    # annotation, so no separate "eksctl create iamserviceaccount" step.
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
      value = aws_iam_role.aws_load_balancer_controller_iam_role.arn
    },
    # Controls the shared backend security group (the k8s-traffic-<cluster>-<hash>
    # group the controller creates and attaches to every load balancer, then uses
    # as the traffic source in the rules it adds to nodes).
    #
    # Rendered as a bare boolean rather than a quoted string. The chart guards
    # this flag with {{ if kindIs "bool" .Values.enableBackendSecurityGroup }},
    # which is a type check, not a truthiness check: a string "false" fails it,
    # the flag is omitted from the Deployment entirely, and the controller falls
    # back to its own default of true - silently the opposite of what was asked.
    # helm --set infers a boolean from "false", so this entry must never carry
    # type = "string" (rules.md E-7/G-2).
    {
      name  = "enableBackendSecurityGroup"
      value = tostring(var.enable_backend_security_group)
    },
    # Whether the chart installs the mservice.elbv2.k8s.aws mutating webhook, whose
    # only job is to make this controller the default for new Services of type
    # LoadBalancer by injecting spec.loadBalancerClass.
    #
    # It is worth turning off because of how widely it reaches. The chart gives it
    # failurePolicy: Fail and no namespaceSelector at all, and its rule matches every
    # v1/services CREATE in the cluster - the sole exclusion is an objectSelector for
    # the controller's own app.kubernetes.io/name label, which is just how the chart
    # avoids deadlocking on its own Service. So for as long as the controller has no
    # Ready pod backing aws-load-balancer-webhook-service, the API server rejects
    # every Service created anywhere:
    #
    #   Internal error occurred: failed calling webhook "mservice.elbv2.k8s.aws":
    #   failed to call webhook: Post "https://aws-load-balancer-webhook-service
    #   .kube-system.svc:443/mutate-v1-service?timeout=10s": no endpoints available
    #   for service "aws-load-balancer-webhook-service"
    #
    # That window is not an edge case: the webhook object is registered during this
    # release's install, well before its Deployment is Available, and it reopens on
    # every controller rollout or node replacement. Any other chart installing
    # Services at that moment fails, and the failure names this webhook rather than
    # anything the caller did.
    #
    # Rendered as a bare boolean, never type = "string". The chart's guard is a plain
    # {{- if .Values.enableServiceMutatorWebhook }}, and a non-empty string is truthy
    # in a Go template - so "false" as a string would leave the webhook installed
    # while appearing to disable it (rules.md E-7).
    {
      name  = "enableServiceMutatorWebhook"
      value = tostring(var.enable_service_mutator_webhook)
    },
    ],
    var.additional_set_values,
  )

  # The role must already carry its inline policy before the controller starts
  # reconciling Ingresses, and referencing the role's ARN alone doesn't order
  # this release after the policy (rules.md D-1).
  depends_on = [aws_iam_role_policy.aws_load_balancer_controller_iam_role]
}
