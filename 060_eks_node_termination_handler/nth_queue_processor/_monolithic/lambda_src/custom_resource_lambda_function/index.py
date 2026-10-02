import boto3
import cfnresponse
import json

def lambda_handler(event, context):
  print(json.dumps(event))
  try:
    if event["RequestType"] == "Delete":
      cfnresponse.send(event, context, cfnresponse.SUCCESS, {})
      return
    cluster_name = event["ResourceProperties"]["ClusterName"]
    nodegroup_name = event["ResourceProperties"]["NodegroupName"]
    eks = boto3.client("eks")
    response = eks.describe_nodegroup(
      clusterName=cluster_name,
      nodegroupName=nodegroup_name
    )
    asg_list = response["nodegroup"]["resources"]["autoScalingGroups"]
    asg_name = asg_list[0]["name"] if asg_list else ""
    cfnresponse.send(event, context, cfnresponse.SUCCESS, {"AutoScalingGroupName": asg_name})
  except Exception as e:
    print(f"Error: {str(e)}")
    cfnresponse.send(event, context, cfnresponse.FAILED, {})
