# Grafana, installed through its operator, querying Amazon Managed Prometheus with SigV4.
#
# The _monolithic template did all of this from an SSM Association: a helm install, then two
# custom resources written as single-quoted shell strings and applied with kubectl. Nothing
# was in state, and the administrator password was interpolated straight into the Grafana
# custom resource - readable to anyone who could get that object, and printed in a Terraform
# output besides.
#
# The IAM role, the Secret, the release and the two custom resources are one component: each
# references the next, and none is useful alone (rules.md C-2).
locals {
  # The operator's naming, not this module's. Getting one wrong produces a rollout wait
  # against a Deployment that does not exist, which reads as a failed install (rules.md B-5).
  deployment_name      = "${var.name}-deployment"
  service_name         = "${var.name}-service"
  service_account_name = "${var.name}-sa"
  admin_secret_name    = "${var.name}-admin-credentials"
  # The label the operator matches an instance against. A GrafanaDatasource whose
  # instanceSelector matches nothing is accepted by the API server and reconciled into
  # nothing - the data source simply never appears in the UI.
  instance_label = { dashboards = var.name }
}
resource "random_password" "admin" {
  count = var.admin_password == null ? 1 : 0

  length = 24
  # Excludes the characters that need escaping when a password is pasted into a shell or a
  # URL, which is where a generated credential usually ends up.
  override_special = "!#%*+-=?_"
}
locals {
  admin_password = var.admin_password != null ? var.admin_password : random_password.admin[0].result
}
resource "aws_iam_role" "grafana_iam_role" {
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
          "${var.oidc_issuer_host}:sub" = "system:serviceaccount:${var.namespace}:${local.service_account_name}"
          "${var.oidc_issuer_host}:aud" = "sts.amazonaws.com"
        }
      }
    }]
  })
}
resource "aws_iam_role_policy_attachment" "grafana_iam_role" {
  for_each = toset(var.iam_policy_arns)

  role       = aws_iam_role.grafana_iam_role.name
  policy_arn = each.value
}
# Scoped to the one workspace, unlike AmazonPrometheusQueryAccess. Both are attached by
# default so the managed policy's name stays visible as the thing this replaces; emptying
# iam_policy_arns leaves only this.
resource "aws_iam_role_policy" "grafana_workspace_query" {
  count = var.inline_workspace_policy ? 1 : 0

  role = aws_iam_role.grafana_iam_role.name
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Action = [
        "aps:QueryMetrics",
        "aps:GetSeries",
        "aps:GetLabels",
        "aps:GetMetricMetadata",
      ]
      Resource = [var.prometheus_workspace_arn]
    }]
  })
}
# Optional, and the only way to retrieve the generated password without reading Terraform
# state. The Kubernetes Secret below is the one Grafana reads; this is for a human.
resource "aws_secretsmanager_secret" "admin" {
  count = var.secrets_manager_name == null ? 0 : 1

  name                    = var.secrets_manager_name
  description             = "Grafana administrator credentials for the ${var.name} instance"
  recovery_window_in_days = 0
}
resource "aws_secretsmanager_secret_version" "admin" {
  count = var.secrets_manager_name == null ? 0 : 1

  secret_id = aws_secretsmanager_secret.admin[0].id
  secret_string = jsonencode({
    username = var.admin_user
    password = local.admin_password
  })
}
resource "helm_release" "grafana_operator" {
  name = "grafana-operator"
  # An OCI reference is passed as the chart with no repository argument.
  chart            = var.operator_chart
  version          = var.operator_chart_version
  namespace        = var.namespace
  create_namespace = true
  # Holds the apply until the operator is Available, which is what the _monolithic script's
  # "--wait" did. The instance it goes on to build is asynchronous, so this does not mean
  # Grafana is up.
  wait    = true
  timeout = var.timeout_seconds
}
# The credential, as a Secret rather than a field in the custom resource.
#
# That is the difference from the _monolithic template. A Grafana custom resource's body is
# not sensitive to Terraform, so a password written into spec.config.security appears in
# plan output and in state's plaintext rendering of the manifest, as well as being readable
# to anyone with get access to that object. Going through a Secret means the manifest below
# carries only a reference.
resource "kubectl_manifest" "admin_secret" {
  # Marked sensitive by the provider for kind: Secret, so the values do not render in plan.
  yaml_body = yamlencode({
    apiVersion = "v1"
    kind       = "Secret"
    metadata = {
      name      = local.admin_secret_name
      namespace = var.namespace
    }
    type = "Opaque"
    stringData = {
      admin_user     = var.admin_user
      admin_password = local.admin_password
    }
  })

  # The namespace is created by the release above, and metadata.namespace is a literal
  # string (rules.md D-1).
  depends_on = [helm_release.grafana_operator]
}
resource "kubectl_manifest" "grafana" {
  yaml_body = yamlencode({
    apiVersion = "grafana.integreatly.org/v1beta1"
    kind       = "Grafana"
    metadata = {
      name      = var.name
      namespace = var.namespace
      # What the GrafanaDatasource below selects on.
      labels = local.instance_label
    }
    spec = merge(
      var.grafana_version == null ? {} : { version = var.grafana_version },
      {
        config = {
          log = {
            mode = "console"
          }
          auth = {
            # A string, because Grafana's config is an ini file and the operator renders
            # every value as one. A bool here is rejected by the CRD schema.
            disable_login_form = "false"
          }
          # No security section. The _monolithic template put admin_user and admin_password
          # here in plaintext; the environment variables below set the same two settings and
          # take precedence over the config file.
        }
        serviceAccount = {
          metadata = {
            annotations = {
              "eks.amazonaws.com/role-arn" = aws_iam_role.grafana_iam_role.arn
            }
          }
        }
        deployment = {
          spec = {
            template = {
              spec = {
                containers = [{
                  name = "grafana"
                  env = [
                    {
                      # Makes the AWS SDK read the web identity token file IRSA projects
                      # into the pod. Without it the SigV4 signer falls back to the
                      # instance role, which has no AMP permissions - and the data source
                      # fails with an authentication error that names neither.
                      name  = "AWS_SDK_LOAD_CONFIG"
                      value = "true"
                    },
                    {
                      name  = "GF_AUTH_SIGV4_AUTH_ENABLED"
                      value = "true"
                    },
                    {
                      # The plugin the data source needs. Grafana installs it at startup,
                      # so the first boot is slower and needs egress.
                      name  = "GF_INSTALL_PLUGINS"
                      value = var.datasource_plugin
                    },
                    {
                      name = "GF_SECURITY_ADMIN_USER"
                      valueFrom = {
                        secretKeyRef = {
                          name = local.admin_secret_name
                          key  = "admin_user"
                        }
                      }
                    },
                    {
                      name = "GF_SECURITY_ADMIN_PASSWORD"
                      valueFrom = {
                        secretKeyRef = {
                          name = local.admin_secret_name
                          key  = "admin_password"
                        }
                      }
                    },
                  ]
                }]
              }
            }
          }
        }
        ingress = {
          spec = {
            # Omitting this leaves the Ingress unclaimed by any controller, which produces
            # no error and no address (rules.md G-1).
            ingressClassName = var.ingress_class_name
            rules = [{
              http = {
                paths = [{
                  path     = var.ingress_path
                  pathType = "Prefix"
                  backend = {
                    service = {
                      name = local.service_name
                      port = {
                        number = var.service_port
                      }
                    }
                  }
                }]
              }
            }]
          }
        }
      },
    )
  })

  # The Secret has to exist before the pod referencing it starts, and the CRD this object is
  # an instance of comes from the release (rules.md D-1).
  depends_on = [helm_release.grafana_operator, kubectl_manifest.admin_secret]
}
resource "kubectl_manifest" "grafana_datasource" {
  yaml_body = yamlencode({
    apiVersion = "grafana.integreatly.org/v1beta1"
    kind       = "GrafanaDatasource"
    metadata = {
      name      = var.datasource_name
      namespace = var.namespace
    }
    spec = {
      datasource = {
        name = var.datasource_name
        # The Amazon Prometheus plugin, not the built-in prometheus type: only it signs
        # requests with SigV4, which is what AMP requires.
        type   = var.datasource_plugin
        access = "proxy"
        # The workspace's base endpoint. Appending api/v1/remote_write here - the value a
        # collector needs - produces 405 on every query, reported as a generic data source
        # error (rules.md B-5).
        url = var.prometheus_endpoint
        jsonData = {
          defaultEditor = "builder"
          sigV4Auth     = true
          # "default" means the credential chain, which under IRSA is the projected web
          # identity token.
          sigV4AuthType = "default"
          # SigV4 signatures are region-scoped; a wrong region produces a signature AMP
          # rejects.
          sigV4Region = var.aws_region
        }
        isDefault = true
        editable  = true
      }
      # Selects the Grafana instance above by label. A selector matching nothing is accepted
      # and reconciled into nothing, so the data source simply never appears.
      instanceSelector = {
        matchLabels = local.instance_label
      }
    }
  })

  depends_on = [kubectl_manifest.grafana]
}
