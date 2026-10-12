# vpc-cni is a networking DaemonSet: worker nodes need it running before they
# can join the cluster in a Ready state, so bootstrap_self_managed_addons must
# be false on the cluster (see modules/eks_cluster) and this module must be
# created before any node capacity. As a DaemonSet it becomes ACTIVE with zero
# nodes (desired == ready == 0), so it only needs the cluster to exist
# (rules.md C-4). Split into its own module - rather than sharing one with
# kube-proxy/coredns - so each EKS-managed addon can be independently
# versioned, upgraded and ordered.
locals {
  # tostring, not the bool itself. The addon's configuration schema declares this key as
  # {"format": "boolean", "type": "string"}, so it has to arrive as the JSON string "true"
  # rather than the JSON literal true. EKS rejects the boolean outright:
  #
  #   InvalidParameterException: ConfigurationValue provided in request is not supported:
  #   Json schema validation failed with error:
  #   [$.enableNetworkPolicy: boolean found, string expected]
  #
  # This is the opposite of helm's --set, where a quoted "false" is inferred as a string
  # and silently breaks a chart's kindIs "bool" guard (rules.md E-7/G-2). The two are not
  # interchangeable: a Helm value wants the real bool, an EKS addon configuration value
  # wants the string. Confirm which with
  #   aws eks describe-addon-configuration --addon-name vpc-cni --addon-version <v>
  # rather than guessing, because only apply surfaces the mismatch - plan cannot, since
  # the schema lives in the EKS API (rules.md E-5).
  configuration = merge(
    length(var.env) > 0 ? { env = var.env } : {},
    var.enable_network_policy != null ? { enableNetworkPolicy = tostring(var.enable_network_policy) } : {},
  )
}
resource "aws_eks_addon" "vpc_cni" {
  cluster_name                = var.cluster_name
  addon_name                  = "vpc-cni"
  addon_version               = var.addon_version
  resolve_conflicts_on_create = var.resolve_conflicts_on_create
  resolve_conflicts_on_update = var.resolve_conflicts_on_update

  # Both halves of this addon's configuration schema, built as one object
  # (rules.md E-5):
  #
  #   env                  - the aws-node DaemonSet's environment variables,
  #                          replacing any "kubectl set env daemonset aws-node
  #                          -n kube-system ..." shell step.
  #   enableNetworkPolicy  - a top-level key, NOT an env var. It switches on the
  #                          network policy agent that enforces Kubernetes
  #                          NetworkPolicy objects. Putting it under env renders
  #                          valid JSON that the addon ignores, so policies are
  #                          accepted by the API server and never enforced.
  #
  # Null/empty members are dropped rather than sent as explicit nulls, so an
  # unconfigured addon gets no configuration_values at all and EKS applies its
  # own defaults.
  configuration_values = length(local.configuration) > 0 ? jsonencode(local.configuration) : null
}
