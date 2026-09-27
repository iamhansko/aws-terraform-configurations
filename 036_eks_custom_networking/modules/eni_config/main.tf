# The piece that makes custom networking actually route pods into the secondary
# CIDR. Turning AWS_VPC_K8S_CNI_CUSTOM_NETWORK_CFG on tells the VPC CNI to stop
# taking pod addresses from the node's own subnet and read an ENIConfig instead;
# these are those ENIConfigs, one per zone.
#
# ENI_CONFIG_LABEL_DEF is set to topology.kubernetes.io/zone on the addon, so the
# CNI looks up an ENIConfig whose name equals the value of that label on the node -
# which is why each resource is named after its availability zone and why the
# caller passes a map keyed by zone.
#
# Declared as raw manifests with alekc/kubectl rather than through
# hashicorp/kubernetes: this is a CRD instance, and kubernetes_manifest resolves a
# resource schema from the API server during plan, which cannot work for a CRD that
# the vpc-cni addon has not installed yet (rules.md E-2/E-3). Field names stay
# camelCase, as the API spells them.
resource "kubectl_manifest" "eni_config" {
  for_each = var.pod_subnets_by_az

  yaml_body = yamlencode({
    apiVersion = "crd.k8s.amazonaws.com/v1alpha1"
    kind       = "ENIConfig"
    metadata = {
      # Cluster-scoped, and the name has to be the zone - not a label, not an
      # annotation. A name that does not match a node's zone label leaves pods on
      # that node unable to get an address, and the CNI logs it rather than
      # failing anything Terraform can see.
      name = each.key
    }
    spec = {
      subnet         = each.value
      securityGroups = var.security_group_ids
    }
  })
}
