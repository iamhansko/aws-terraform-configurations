import boto3
import cfnresponse
import json

def lambda_handler(event, context):
  print(json.dumps(event))
  try:
    if event["RequestType"] == "Delete":
      cfnresponse.send(event, context, cfnresponse.SUCCESS, {})
      return
    ec2 = boto3.client("ec2")
    prefix_list_name = event["ResourceProperties"]["PrefixListName"]
    prefix_list_data = ec2.describe_managed_prefix_lists(Filters=[{"Name":"prefix-list-name","Values":[prefix_list_name]}])
    prefix_list_id = prefix_list_data["PrefixLists"][0]["PrefixListId"]
    cfnresponse.send(event, context, cfnresponse.SUCCESS, {"PrefixListId": prefix_list_id})
  except Exception as error:
    print(f"Error: {str(e)}")
    cfnresponse.send(event, context, cfnresponse.FAILED, {}, reason=str(error))
