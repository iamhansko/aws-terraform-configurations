import json
import cfnresponse
import boto3

s3 = boto3.client("s3")

def handler(event, context):
  print(f"Event : {json.dumps(event)}")
  response_data = {}

  try:
    request_type = event["RequestType"]
    s3_bucket = event["ResourceProperties"]["S3Bucket"]
    s3_object_key = event["ResourceProperties"]["S3ObjectKey"]
    template_body = event["ResourceProperties"]["TemplateBody"]

    if request_type in ("Create", "Update"):
      s3.put_object(Bucket=s3_bucket, Key=s3_object_key, Body=template_body.encode("utf-8"))
      response_data["Message"] = "Custom Resource Created/Updated"
    elif request_type == "Delete":
      s3.delete_object(Bucket=s3_bucket, Key=s3_object_key)
      response_data["Message"] = "Custom Resource Deleted"
    cfnresponse.send(event, context, cfnresponse.SUCCESS, response_data)
  except Exception as e:
    response_data["Reason"] = str(e)
    cfnresponse.send(event, context, cfnresponse.FAILED, response_data)
