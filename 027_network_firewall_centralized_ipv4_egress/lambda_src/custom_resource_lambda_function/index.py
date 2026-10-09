import boto3
import cfnresponse
import json
def lambda_handler(event, context):
  print(json.dumps(event))
  try:
    ec2 = boto3.client("ec2")
    tgw_id = event["ResourceProperties"]["TransitGatewayId"]
    tgw_data = ec2.describe_transit_gateways(TransitGatewayIds=[tgw_id])
    tgw_default_rt_id = None
    if tgw_data["TransitGateways"]:
      options = tgw_data["TransitGateways"][0].get("Options", {})
      tgw_default_rt_id = options.get("AssociationDefaultRouteTableId", None)
    if not tgw_default_rt_id:
      raise Exception("TransitGateway DefaultRouteTableId Not Found")
    cfnresponse.send(event, context, cfnresponse.SUCCESS, {"DefaultRouteTableId": tgw_default_rt_id})
  except Exception as e:
    cfnresponse.send(event, context, cfnresponse.FAILED, {"Message": str(e)})