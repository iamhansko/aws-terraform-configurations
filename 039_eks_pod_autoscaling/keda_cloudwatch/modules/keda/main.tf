# The role the operator assumes to read CloudWatch. It lives in the same module as
# the release that annotates its service account with the ARN, because IRSA is one
# component: the trust policy names a namespace and service account the chart
# creates, and the chart needs an ARN only this role can provide (rules.md C-2).
resource "aws_iam_role" "keda_operator" {
  name = var.role_name
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Federated = var.oidc_provider_arn }
      Action    = "sts:AssumeRoleWithWebIdentity"
      Condition = {
        StringEquals = {
          # Restricts the role to exactly one pod identity in the cluster. Without the
          # sub condition any service account with a projected token from this issuer
          # could assume it.
          "${var.oidc_issuer_host}:sub" = "system:serviceaccount:${var.namespace}:${var.service_account_name}"
          "${var.oidc_issuer_host}:aud" = var.irsa_audience
        }
      }
    }]
  })
}
# for_each rather than one attachment resource per policy, so the list can be extended
# by a caller without editing this module (rules.md B-7). toset is safe here because
# these are literal ARNs, known at plan time - the same pattern would fail on IDs that
# come out of another module (rules.md B-8).
resource "aws_iam_role_policy_attachment" "keda_operator" {
  for_each   = toset(var.iam_policy_arns)
  role       = aws_iam_role.keda_operator.name
  policy_arn = each.value
}
# The _monolithic template installed this from an SSM Association on the bastion, and
# passed --set podIdentity.aws.irsa.roleArn="{KedaOperatorRole.Arn}" - an
# unconverted CloudFormation reference that reached the cluster as that literal
# string. The service account was therefore annotated with a role ARN that does not
# exist, so every AWS-backed scaler failed to authenticate, and the only sign of it
# was a ScaledObject whose metric never resolved. Reading the ARN off the resource
# above removes the class of mistake entirely (rules.md E-1).
resource "helm_release" "keda" {
  name             = var.release_name
  repository       = var.chart_repository
  chart            = "keda"
  version          = var.chart_version
  namespace        = var.namespace
  create_namespace = var.create_namespace
  # Holds the apply until the operator, metrics server and webhook are Available,
  # which is what the _monolithic script's "helm ... --wait" did. It matters more than
  # usual here: the CRDs arrive with this release, and the ScaledObject in
  # modules/keda_scaled_object cannot be applied until they are registered.
  wait    = true
  timeout = var.timeout_seconds
  set = concat([
    {
      name = "podIdentity.aws.irsa.enabled"
      # Left to auto inference so it reaches the chart as a boolean (rules.md E-7).
      value = "true"
    },
    {
      name  = "podIdentity.aws.irsa.roleArn"
      value = aws_iam_role.keda_operator.arn
      # This becomes the eks.amazonaws.com/role-arn annotation on the service
      # account, and annotation values have to be strings (rules.md E-7).
      type = "string"
    },
    {
      name  = "podIdentity.aws.irsa.audience"
      value = var.irsa_audience
      type  = "string"
    },
    ],
    var.additional_set_values,
  )
  # The policies have to be attached before the operator starts using the role, and
  # the attachments are not referenced by anything above - only the role itself is -
  # so nothing else orders them (rules.md D-1).
  depends_on = [aws_iam_role_policy_attachment.keda_operator]
}
