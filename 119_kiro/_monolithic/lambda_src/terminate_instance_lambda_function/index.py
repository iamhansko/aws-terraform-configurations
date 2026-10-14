import boto3
import cfnresponse
import json

def lambda_handler(event, context):
  print(f"Event : {json.dumps(event)}")
  response_data = {}

  try:
    request_type = event["RequestType"]
    instance_id = event["ResourceProperties"].get("InstanceId", "")

    if not instance_id:
      response_data["Reason"] = "No EC2 Instance ID"
      cfnresponse.send(event, context, cfnresponse.FAILED, response_data)
      return

    ec2 = boto3.client("ec2")
    if request_type == "Create" or request_type == "Update":
      try:
        response = ec2.describe_instances(InstanceIds=[instance_id])
        instances = response["Reservations"][0]["Instances"]
        instance_state = instances[0]["State"]["Name"]
        if instance_state not in ["terminated", "terminating"]:
          terminate_response = ec2.terminate_instances(InstanceIds=[instance_id])
          response_data["Message"] = f"{instance_id} Termination Requested"
          response_data["PreviousState"] = instance_state
        else:
          response_data["Message"] = f"{instance_id}"
          response_data["PreviousState"] = instance_state
      except Exception as e:
        response_data["Reason"] = str(e)
        cfnresponse.send(event, context, cfnresponse.FAILED, response_data)
        return
    elif request_type == "Delete":
      response_data["Message"] = "Custom Resource Deleted"

    cfnresponse.send(event, context, cfnresponse.SUCCESS, response_data)

  except Exception as e:
    response_data["Reason"] = str(e)
    cfnresponse.send(event, context, cfnresponse.FAILED, response_data)
