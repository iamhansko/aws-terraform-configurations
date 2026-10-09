import json
import os
import boto3

sqs = boto3.client('sqs')
QUEUE_URL = os.environ['QUEUE_URL']

def lambda_handler(event, context):
  body = json.loads(event["body"])
  sqs.send_message(QueueUrl=QUEUE_URL, MessageBody=body["message"])
  return {"statusCode": 200, "body": "Success"}
