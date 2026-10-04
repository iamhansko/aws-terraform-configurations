import json
import time
import cfnresponse
import boto3
s3 = boto3.resource("s3")
def handler(event, context):
  print(f"Event : {json.dumps(event)}")
  response_data = {}
  try:
    request_type = event["RequestType"]
    s3_bucket = event["ResourceProperties"]["S3Bucket"]

    if request_type == "Create":
      response_data["Message"] = "Custom Resource Created"
    elif request_type == "Update":
      response_data["Message"] = "Custom Resource Updated"
    elif request_type == "Delete":
      bucket = s3.Bucket(s3_bucket)
      bucket.objects.all().delete()
      response_data["Message"] = "Custom Resource Deleted"
    cfnresponse.send(event, context, cfnresponse.SUCCESS, response_data)
  except Exception as e:
    response_data["Message"] = "Error"
    cfnresponse.send(event, context, cfnresponse.FAILED, response_data, reason=str(e))
