import boto3
import cfnresponse
import json

def lambda_handler(event, context):
  print(f"Event : {json.dumps(event)}")
  response_data = {}

  try:
    request_type = event["RequestType"]
    parameter_name = event["ResourceProperties"].get("ParameterName", "")

    if not parameter_name:
      response_data["Reason"] = "No ParameterName"
      cfnresponse.send(event, context, cfnresponse.FAILED, response_data)
      return

    ssm = boto3.client("ssm")
    if request_type == "Create" or request_type == "Update":
      try:
        response = ssm.get_parameter(Name=parameter_name,WithDecryption=True)
        response_data["Value"] = response["Parameter"]["Value"]
        response_data["Type"] = response["Parameter"]["Type"]
        response_data["Name"] = parameter_name
        response_data["Message"] = f"{parameter_name}"
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
