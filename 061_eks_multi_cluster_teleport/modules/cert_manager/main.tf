# cert-manager, plus the one issuer this project needs it for.
#
# Teleport's chart creates a Certificate for its own hostname and leaves the issuing to
# cert-manager, so without this there is no TLS and the proxy never becomes ready. The
# certificate is validated over DNS-01 rather than HTTP-01, because the name being proved
# includes a wildcard - and Let's Encrypt only issues wildcards against a DNS challenge.
#
# That is what makes the IAM role here necessary: the solver has to write a TXT record
# into the hosted zone and then read it back.
resource "aws_iam_role" "cert_manager_iam_role" {
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
          "${var.oidc_issuer_host}:sub" = "system:serviceaccount:${var.namespace}:${var.release_name}"
          "${var.oidc_issuer_host}:aud" = "sts.amazonaws.com"
        }
      }
    }]
  })
}
# Scoped to the one hosted zone. The _monolithic template put the equivalent permissions
# on the node instance role instead, which hands them to every pod on every node through
# IMDS - and the ability to rewrite records in a zone is the ability to take over the name
# the cluster authenticates with.
resource "aws_iam_role_policy" "cert_manager_iam_role" {
  role = aws_iam_role.cert_manager_iam_role.name
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        # Polling a change set until it is INSYNC. Not scopeable to a zone: the change ID
        # is not part of the zone's ARN.
        Effect   = "Allow"
        Action   = ["route53:GetChange"]
        Resource = ["arn:aws:route53:::change/*"]
      },
      {
        Effect   = "Allow"
        Action   = ["route53:ChangeResourceRecordSets", "route53:ListResourceRecordSets"]
        Resource = ["arn:aws:route53:::hostedzone/${var.route53_hosted_zone_id}"]
      },
      {
        # Only needed when a solver has no hostedZoneID and cert-manager has to find the
        # zone by name. This one does specify it, so this is here for the case where that
        # is removed - the action cannot be scoped to a zone at all, which is why keeping
        # the ID in the solver below is worth doing.
        Effect   = "Allow"
        Action   = ["route53:ListHostedZonesByName"]
        Resource = ["*"]
      },
    ]
  })
}
resource "helm_release" "cert_manager" {
  name             = var.release_name
  repository       = var.chart_repository
  chart            = "cert-manager"
  version          = var.chart_version
  namespace        = var.namespace
  create_namespace = true
  # Holds the apply until the webhook is actually serving. Without it the next release can
  # start creating Certificate objects while the webhook is still coming up, and those
  # requests fail with a connection error rather than queueing - which is what the
  # _monolithic script's "--wait" was there for.
  wait    = true
  timeout = var.timeout_seconds

  set = concat([
    {
      # crds.enabled in current chart versions; the chart used to call this installCRDs -
      # which the _monolithic template passed - and the old name is accepted while
      # installing nothing at all.
      name  = "crds.enabled"
      value = tostring(var.install_crds)
    },
    {
      name  = "serviceAccount.name"
      value = var.release_name
    },
    {
      # The IRSA annotation. A string, because Kubernetes annotation values must be
      # strings and helm's type inference would otherwise be free to decide otherwise
      # (rules.md E-7). The escaped dots are helm --set path syntax, not part of the key.
      name  = "serviceAccount.annotations.eks\\.amazonaws\\.com/role-arn"
      value = aws_iam_role.cert_manager_iam_role.arn
      type  = "string"
    },
    ],
    var.additional_set_values,
  )

  # The controller cannot assume the role until the role carries its policy, and
  # referencing the ARN alone does not order this after the policy (rules.md D-1).
  depends_on = [aws_iam_role_policy.cert_manager_iam_role]
}
# A ClusterIssuer rather than a namespaced Issuer, and that is a deliberate difference from
# the _monolithic template.
#
# cert-manager treats credentials it picks up from its own environment - which is what
# IRSA is - as "ambient", and refuses to let a namespaced Issuer use them unless the
# controller is started with --issuer-ambient-credentials. The template set exactly that
# flag, which grants every Issuer in every namespace the use of cert-manager's identity:
# anyone able to create an Issuer could then rewrite records in the hosted zone. Ambient
# credentials are allowed for a ClusterIssuer by default, because only a cluster
# administrator can create one, so this needs no flag.
resource "kubectl_manifest" "cluster_issuer" {
  yaml_body = yamlencode({
    apiVersion = "cert-manager.io/v1"
    kind       = "ClusterIssuer"
    metadata = {
      name = var.issuer_name
    }
    spec = {
      acme = {
        email  = var.issuer_email
        server = var.acme_server
        privateKeySecretRef = {
          # Where the ACME account key is stored. For a ClusterIssuer this lands in
          # cert-manager's own namespace rather than the issuer's, since a cluster-scoped
          # object has none.
          name = var.issuer_name
        }
        solvers = [{
          selector = {
            dnsZones = [var.dns_zone]
          }
          dns01 = {
            route53 = {
              region = var.aws_region
              # Stated rather than discovered. Without it cert-manager calls
              # ListHostedZonesByName and picks the closest match, which on an account
              # with several zones for related names is a guess.
              hostedZoneID = var.route53_hosted_zone_id
            }
          }
        }]
      }
    }
  })

  # The CRD this object is an instance of is installed by the release above, and nothing
  # in its body references the release (rules.md D-1/E-2).
  depends_on = [helm_release.cert_manager]
}
