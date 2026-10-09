# The transit gateway, and nothing else.
#
# No attachments and no routes in this module, which is a different call from the transit_gateway
# module in 109_eks_cross_vpc_tgw. There, the gateway owns its attachments and each VPC module is
# handed the gateway's id to write its own routes with. That shape works only as long as no module
# carries depends_on: an attachment needs a VPC's subnets, and a VPC's route needs the gateway, so
# the two modules reference each other and any module-level depends_on between them closes a cycle
# Terraform refuses to build.
#
# This root needs those depends_on edges - rules.md D-3 wants every module ordered after the VPCs -
# so the pieces that touch both sides are lifted into the root instead: the two attachments, the
# gateway's own route, and the two VPC routes that point at the gateway (rules.md C-1). What is left
# here depends on nothing and can therefore safely be ordered after both VPC modules.
resource "aws_ec2_transit_gateway" "transit_gateway" {
  description = var.description
  # Both default behaviours enabled, as the _monolithic template had them, and that choice is what
  # the deleted Lambda function existed to work around.
  #
  # With association enabled every attachment lands in the gateway's own default route table rather
  # than one this configuration created, and with propagation enabled each attachment's VPC CIDR is
  # advertised into that table automatically. So the app VPC's 172.16.0.0/16 route - the return half
  # of every connection - is installed by AWS and appears in no plan. The only route written here is
  # the default one, and it has to go into that same AWS-managed table.
  #
  # 109_eks_cross_vpc_tgw disables both and creates its own route table, which makes every route
  # visible in configuration. That is the better default for anything long-lived. It is not what this
  # template did, and the id lookup below is only interesting because this one is enabled.
  default_route_table_association = "enable"
  default_route_table_propagation = "enable"
  auto_accept_shared_attachments  = var.auto_accept_shared_attachments
  dns_support                     = "enable"
  vpn_ecmp_support                = "enable"
  tags = {
    Name = var.name
  }
}
