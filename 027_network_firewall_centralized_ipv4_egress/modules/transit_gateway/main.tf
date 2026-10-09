# The hub. Just the gateway - the two VPC attachments and the static default route are declared in the
# root, because an attachment needs both this gateway and a VPC that another module owns, and joining two
# modules' outputs is the root's job (rules.md C-1).
#
# This module is also where a Lambda function, an IAM role, an inline ec2:* policy, a role policy
# attachment, an archive_file data source, the archive provider and a lambda_src/ tree used to live. All of
# it has been deleted, and the reason is the output below: association_default_route_table_id.
#
# What the original did
# ---------------------
# CloudFormation's AWS::EC2::TransitGateway does not return the id of the route table it creates when
# DefaultRouteTableAssociation is enabled. The template therefore shipped a custom resource: a Python
# function that called ec2:DescribeTransitGateways and pulled Options.AssociationDefaultRouteTableId out of
# the response, so that the static route could name a route table id. That value was consumed in exactly
# one place - the transit_gateway_route_table_id of the one aws_ec2_transit_gateway_route - and nowhere
# else.
#
# Why it is gone
# --------------
# The AWS provider exposes the same value as an attribute of the gateway itself, so the function was
# solving a CloudFormation limitation that Terraform does not have. Replacing it removes a function, a
# role, a policy granting ec2:* on "*", a build artifact and a provider, and turns a runtime API call into
# a resource attribute that plan can read.
#
# The converted version could not have worked anyway, which is worth recording so nobody tries to revive
# it. Four independent reasons, any one fatal:
#
#   1. The handler reported its result with cfnresponse.send(...), which POSTs to event['ResponseURL'].
#      aws_lambda_invocation does a synchronous invoke and reads the function's *return value*; the
#      handler returns None.
#   2. cfnresponse is injected by AWS only into functions whose code is inlined as ZipFile in a
#      CloudFormation template. This function was packaged from disk with archive_file, so "import
#      cfnresponse" raises ModuleNotFoundError before any of the rest runs.
#   3. The handler read event["ResourceProperties"]["TransitGatewayId"]. Terraform's payload was
#      {"TransitGatewayId": ...} with no ResourceProperties wrapper, so that is a KeyError.
#   4. There is no ResponseURL in Terraform's payload for cfnresponse to post to even if 1-3 were fixed.
#
# The same defect is documented in 096_s3_static_website's lambda_src and in
# 102_windows_rdp/modules/app_secret. lambda_src/custom_resource_lambda_function/index.py is still on disk
# in this project and is referenced by nothing - see the note in the root's providers.tf.
resource "aws_ec2_transit_gateway" "tgw" {
  description                     = var.description
  default_route_table_association = var.default_route_table_association
  default_route_table_propagation = var.default_route_table_propagation
  auto_accept_shared_attachments  = var.auto_accept_shared_attachments
  dns_support                     = var.dns_support
  vpn_ecmp_support                = var.vpn_ecmp_support
  tags = {
    Name = var.name
  }
}
