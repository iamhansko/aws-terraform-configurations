import json
import uuid
import cfnresponse
def handler(event, context):
  print(f"Event : {json.dumps(event)}")
  request_type = event["RequestType"]
  response_data = {}
  try:
    if request_type == "Create":
      value = str(uuid.uuid4())
    elif request_type == "Update":
      value = event["PhysicalResourceId"]
    elif request_type == "Delete":
      value = event["PhysicalResourceId"]
    response_data["Value"] = value
    cfnresponse.send(event, context, cfnresponse.SUCCESS, response_data, value)
  except Exception as e:
    response_data["Message"] = "Error"
    cfnresponse.send(event, context, cfnresponse.FAILED, response_data, reason=str(e))
