# The amazon-cloudwatch-observability addon and the IAM role its CloudWatch
# agent assumes live in one module: aws_eks_addon's pod_identity_association
# references the role directly, so splitting them would only add an ARN round
# trip through root variables for resources that cannot exist apart
# (rules.md C-2). Own module per addon, as with vpc-cni/kube-proxy/coredns
# (rules.md C-4).
#
# Unlike the EBS/EFS/S3 CSI drivers this uses EKS Pod Identity rather than IRSA:
# the trust policy names pods.eks.amazonaws.com instead of the cluster's OIDC
# provider, so there is no issuer URL to thread through and the same role works
# unchanged if the cluster is replaced. It does mean the eks-pod-identity-agent
# addon has to be running, which the root module orders with depends_on.
locals {
  # The eight per-component pipelines in the _monolithic template were eight
  # copies of one 60-line block, differing only in the component name and the
  # log paths - and the name appeared nine times per copy (tag, DB filename,
  # five Match lines, log group, stream prefix), so adding a component meant
  # nine careful edits. Rendering them from one template over a map makes the
  # component list the only thing anyone has to touch (rules.md B-7 applied to
  # config text rather than resources).
  #
  # The $${...} sequences are Fluent Bit's own env var references, escaped so
  # Terraform passes them through: the addon fills READ_FROM_HEAD, AWS_REGION,
  # CLUSTER_NAME and HOST_NAME in at runtime. $pod is a Fluent Bit record
  # accessor, not an interpolation, so it needs no escaping.
  component_conf_files = {
    for name, paths in var.container_log_components : "${name}.conf" => <<-EOT
      [INPUT]
          Name                tail
          Tag                 ${name}.*
          Path                ${join(", ", paths)}
          multiline.parser    docker, cri
          DB                  /var/fluent-bit/state/flb-${name}.db
          Mem_Buf_Limit       ${var.mem_buf_limit}
          Skip_Long_Lines     On
          Refresh_Interval    ${var.refresh_interval_seconds}
          Rotate_Wait         ${var.rotate_wait_seconds}
          storage.type        filesystem
          Read_from_Head      $${READ_FROM_HEAD}

      [FILTER]
          Name                kubernetes
          Match               ${name}.*
          Kube_Tag_Prefix     ${name}.var.log.containers.
          Kube_URL            https://kubernetes.default.svc:443
          Merge_Log           On
          Merge_Log_Key       log_processed
          K8S-Logging.Parser  On
          K8S-Logging.Exclude Off
          Labels              Off
          Annotations         Off
          Use_Kubelet         On
          Kubelet_Port        ${var.kubelet_port}
          Buffer_Size         0
          Use_Pod_Association On

      [FILTER]
          Name                nest
          Match               ${name}.*
          Operation           lift
          Nested_under        kubernetes

      [FILTER]
          Name                modify
          Match               ${name}.*
          Rename              pod_name pod
          Rename              container_name container
          Rename              namespace_name namespace
          Rename              host node

      [FILTER]
          Name                record_modifier
          Match               ${name}.*
          Allowlist_key       log
          Allowlist_key       pod
          Allowlist_key       container
          Allowlist_key       namespace
          Allowlist_key       node

      [OUTPUT]
          Name                cloudwatch_logs
          Match               ${name}.*
          region              $${AWS_REGION}
          log_group_name      /aws/eks/$${CLUSTER_NAME}/${name}
          log_stream_prefix   ${name}-
          log_stream_template $pod.FROM.$${HOST_NAME}
          auto_create_group   true
          extra_user_agent    container-insights
          add_entity          true
      EOT
  }
  # An empty string replaces the addon's own file rather than removing it, which
  # is how the addon's chart lets a pipeline be switched off: the file still
  # exists, it just declares nothing.
  disabled_default_conf_files = var.disable_default_container_logs ? {
    "application-log.conf" = ""
    "dataplane-log.conf"   = ""
  } : {}
  extra_files = merge(local.disabled_default_conf_files, local.component_conf_files, var.additional_extra_files)
}
resource "aws_iam_role" "cloud_watch_observability_iam_role" {
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = {
        Service = ["pods.eks.amazonaws.com"]
      }
      # Pod Identity needs sts:TagSession alongside sts:AssumeRole: EKS tags the
      # session with the cluster, namespace and service account, and without the
      # permission the agent's pods fail to get credentials at all.
      Action = ["sts:AssumeRole", "sts:TagSession"]
    }]
  })
}
resource "aws_iam_role_policy_attachment" "cloud_watch_observability_iam_role" {
  for_each   = toset(var.iam_policy_arns)
  role       = aws_iam_role.cloud_watch_observability_iam_role.name
  policy_arn = each.value
}
resource "aws_eks_addon" "cloud_watch_observability" {
  cluster_name                = var.cluster_name
  addon_name                  = "amazon-cloudwatch-observability"
  addon_version               = var.addon_version
  resolve_conflicts_on_create = var.resolve_conflicts_on_create
  resolve_conflicts_on_update = var.resolve_conflicts_on_update
  pod_identity_association {
    role_arn        = aws_iam_role.cloud_watch_observability_iam_role.arn
    service_account = var.service_account_name
  }
  # jsonencode rather than the _monolithic template's hand-escaped YAML string,
  # where every newline in 700 lines of Fluent Bit config was a literal \n and a
  # single missing one silently changed the parsed config (rules.md E-5).
  configuration_values = jsonencode({
    containerLogs = {
      fluentBit = {
        config = {
          extraFiles = local.extra_files
        }
      }
    }
  })
  # The role must already carry CloudWatchAgentServerPolicy before the agent
  # starts publishing, and pod_identity_association alone doesn't order this
  # resource after the attachments (rules.md D-1).
  depends_on = [aws_iam_role_policy_attachment.cloud_watch_observability_iam_role]
}
