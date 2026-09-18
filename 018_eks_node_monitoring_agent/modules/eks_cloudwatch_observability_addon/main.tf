locals {
  # The Fluent Bit input that makes this project work: it tails the Node Monitoring
  # Agent's own container log and ships it to a per-cluster CloudWatch log group, so
  # the condition the agent detects is readable without kubectl.
  #
  # $${...} is a literal ${...} after Terraform's interpolation - these are Fluent Bit
  # variables the agent's container substitutes at runtime, not Terraform ones. The
  # _monolithic template carried the same doubling for the same reason.
  node_monitoring_agent_conf = <<-EOT
    [INPUT]
      Name                tail
      Tag                 node-monitoring-agent.*
      Path                /var/log/containers/eks-node-monitoring-agent-*_kube-system_*.log
      multiline.parser    docker, cri
      DB                  /var/fluent-bit/state/flb-node-monitoring-agent.db
      Mem_Buf_Limit       50MB
      Skip_Long_Lines     On
      Refresh_Interval    10
      Rotate_Wait         30
      storage.type        filesystem
      Read_from_Head      $${READ_FROM_HEAD}

    [FILTER]
      Name                kubernetes
      Match               node-monitoring-agent.*
      Kube_Tag_Prefix     node-monitoring-agent.var.log.containers.
      Kube_URL            https://kubernetes.default.svc:443
      Merge_Log           On
      Merge_Log_Key       log_processed
      K8S-Logging.Parser  On
      K8S-Logging.Exclude Off
      Labels              Off
      Annotations         Off
      Use_Kubelet         On
      Kubelet_Port        10250
      Buffer_Size         0
      Use_Pod_Association On

    [FILTER]
      Name                nest
      Match               node-monitoring-agent.*
      Operation           lift
      Nested_under        kubernetes

    [FILTER]
      Name                modify
      Match               node-monitoring-agent.*
      Rename              pod_name pod
      Rename              container_name container
      Rename              namespace_name namespace
      Rename              host node

    [FILTER]
      Name                record_modifier
      Match               node-monitoring-agent.*
      Allowlist_key       log
      Allowlist_key       pod
      Allowlist_key       container
      Allowlist_key       namespace
      Allowlist_key       node

    [OUTPUT]
      Name                cloudwatch_logs
      Match               node-monitoring-agent.*
      region              $${AWS_REGION}
      log_group_name      /aws/eks/$${CLUSTER_NAME}/node-monitoring-agent
      log_stream_prefix   node-monitoring-agent-
      log_stream_template $pod.FROM.$${HOST_NAME}
      auto_create_group   true
      extra_user_agent    container-insights
      add_entity          true
  EOT
}
resource "aws_eks_addon" "cloudwatch_observability" {
  cluster_name                = var.cluster_name
  addon_name                  = "amazon-cloudwatch-observability"
  addon_version               = var.addon_version
  resolve_conflicts_on_create = var.resolve_conflicts_on_create
  resolve_conflicts_on_update = var.resolve_conflicts_on_update

  # EKS Pod Identity rather than IRSA: the addon supports an association declared
  # right here, so the CloudWatch agent's service account gets its role without an
  # OIDC trust policy and without the addon having to know an OIDC issuer
  # (rules.md C-2 keeps role and consumer together; here the addon resource is the
  # consumer).
  pod_identity_association {
    role_arn        = var.pod_identity_role_arn
    service_account = var.service_account_name
  }

  # A YAML document, not JSON, which the addon accepts as configuration_values. The
  # two empty extraFiles switch off the addon's default application and dataplane log
  # pipelines, leaving only the Node Monitoring Agent one below - this project is about
  # that agent's output, and the defaults would bury it.
  configuration_values = yamlencode({
    containerLogs = {
      fluentBit = {
        config = {
          extraFiles = {
            "application-log.conf"       = ""
            "dataplane-log.conf"         = ""
            "node-monitoring-agent.conf" = local.node_monitoring_agent_conf
          }
        }
      }
    }
  })

  # Pod Identity associations are resolved by the eks-pod-identity-agent addon, so it
  # has to be running before this one can use the association above. Nothing in the
  # value references says so (rules.md D-1).
  depends_on = [var.pod_identity_agent_dependency]
}
