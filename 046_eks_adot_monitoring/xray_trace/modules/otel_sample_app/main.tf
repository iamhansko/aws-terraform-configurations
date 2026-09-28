# Something that produces traces, and something that keeps it busy.
#
# An OTLP ingest collector with nothing sending to it is a Service nobody calls, so the
# X-Ray console stays empty and there is no way to tell a working pipeline from a broken
# one. These five objects are what make the variant checkable.
#
# The _monolithic template wrote both manifests as single-quoted shell strings inside an SSM
# Association parameter and applied them with kubectl from the bastion, so neither was in
# state: no diff in plan, nothing removed on destroy, and a YAML indentation error would have
# appeared only in the association's output (rules.md E-1/E-2).
resource "aws_iam_role" "sample_app_iam_role" {
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
# The sample application's /aws-sdk-call endpoint lists S3 buckets, and that is the whole
# extent of what it does with AWS. The _monolithic template attached AmazonS3FullAccess for
# it - read, write and delete on every bucket in the account, to satisfy one ListBuckets.
#
# s3:ListAllMyBuckets cannot be scoped to a resource; it is account-wide by definition, which
# is why the resource is "*" here. That is the correct form for this action rather than a
# concession.
resource "aws_iam_role_policy" "sample_app_iam_role" {
  role = aws_iam_role.sample_app_iam_role.name
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = ["s3:ListAllMyBuckets"]
      Resource = "*"
    }]
  })
}
resource "kubectl_manifest" "service_account" {
  yaml_body = yamlencode({
    apiVersion = "v1"
    kind       = "ServiceAccount"
    metadata = {
      name      = var.service_account_name
      namespace = var.namespace
      annotations = {
        # A string, as Kubernetes requires every annotation value to be (rules.md E-7).
        "eks.amazonaws.com/role-arn" = aws_iam_role.sample_app_iam_role.arn
      }
    }
  })
}
resource "kubectl_manifest" "sample_app_service" {
  yaml_body = yamlencode({
    apiVersion = "v1"
    kind       = "Service"
    metadata = {
      name      = var.sample_app_name
      namespace = var.namespace
      labels    = { app = var.sample_app_name }
    }
    spec = {
      # ClusterIP: the only caller is the traffic generator, inside the cluster.
      type     = "ClusterIP"
      selector = { app = var.sample_app_name }
      ports = [{
        name       = "http"
        port       = var.sample_app_port
        targetPort = var.sample_app_port
        protocol   = "TCP"
      }]
    }
  })
}
resource "kubectl_manifest" "sample_app_deployment" {
  yaml_body = yamlencode({
    apiVersion = "apps/v1"
    kind       = "Deployment"
    metadata = {
      name      = var.sample_app_name
      namespace = var.namespace
      labels    = { app = var.sample_app_name }
    }
    spec = {
      replicas = var.replicas
      selector = {
        matchLabels = { app = var.sample_app_name }
      }
      # Recreate, as the _monolithic template had it. A rolling update would hold two JVMs
      # on a two-node cluster for the length of the rollout.
      strategy = { type = "Recreate" }
      template = {
        metadata = {
          labels = { app = var.sample_app_name }
        }
        spec = {
          # serviceAccountName, not the deprecated serviceAccount the _monolithic template
          # used. Both work; only this one is the field the API documents, and it is what
          # binds the pod to the IRSA annotation above.
          serviceAccountName = var.service_account_name
          containers = [{
            name  = var.sample_app_name
            image = var.sample_app_image
            ports = [{
              name          = "http"
              containerPort = var.sample_app_port
            }]
            env = [
              {
                name  = "AWS_REGION"
                value = var.aws_region
              },
              {
                name  = "LISTEN_ADDRESS"
                value = "0.0.0.0:${var.sample_app_port}"
              },
              {
                # Where the traces go. The collector's Service name is chosen by the add-on,
                # so this value is passed in rather than written here (rules.md B-5).
                name  = "OTEL_EXPORTER_OTLP_ENDPOINT"
                value = var.otlp_endpoint
              },
              {
                # How the traces are labelled in X-Ray. Not Kubernetes namespaces - these
                # are what the service map's nodes are called.
                name  = "OTEL_RESOURCE_ATTRIBUTES"
                value = "service.namespace=${var.otel_service_namespace},service.name=${var.otel_service_name}"
              },
            ]
            resources = {
              requests = {
                cpu    = var.cpu_request
                memory = var.memory_request
              }
            }
          }]
        }
      }
    }
  })

  # The service account has to exist before a pod can reference it; serviceAccountName is a
  # literal string, so Terraform's graph does not otherwise know (rules.md D-1).
  depends_on = [kubectl_manifest.service_account]
}
resource "kubectl_manifest" "traffic_generator_deployment" {
  yaml_body = yamlencode({
    apiVersion = "apps/v1"
    kind       = "Deployment"
    metadata = {
      name      = var.traffic_generator_name
      namespace = var.namespace
      labels    = { app = var.traffic_generator_name }
    }
    spec = {
      replicas = var.replicas
      selector = {
        matchLabels = { app = var.traffic_generator_name }
      }
      template = {
        metadata = {
          labels = { app = var.traffic_generator_name }
        }
        spec = {
          containers = [{
            name    = var.traffic_generator_name
            image   = var.traffic_generator_image
            command = ["/bin/sh", "-c"]
            # busybox wget rather than curl, because the image is plain Alpine - see
            # var.traffic_generator_image. -q -O /dev/null discards the body; the point is
            # the request, not the response. The initial sleep gives the JVM time to bind
            # its port, and the loop never exits, so restartPolicy never comes into play.
            args = [
              join(" ", [
                "sleep 30;",
                "while :; do",
                "wget -q -O /dev/null -T 5 http://${var.sample_app_name}.${var.namespace}.svc.cluster.local:${var.sample_app_port}/outgoing-http-call || true;",
                "sleep 2;",
                "wget -q -O /dev/null -T 5 http://${var.sample_app_name}.${var.namespace}.svc.cluster.local:${var.sample_app_port}/aws-sdk-call || true;",
                "sleep 5;",
                "done",
              ])
            ]
            resources = {
              requests = {
                cpu    = "10m"
                memory = "16Mi"
              }
            }
          }]
        }
      }
    }
  })

  # The Service it calls has to exist, and the name it resolves is a literal string
  # (rules.md D-1). Without this the generator's first few requests fail on DNS, which is
  # harmless but produces a confusing first minute of logs.
  depends_on = [kubectl_manifest.sample_app_service]
}
