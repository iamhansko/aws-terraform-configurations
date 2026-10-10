# The function the workbench packages into the container image and Lambda runs.
#
# This is the handler the _monolithic template wrote with an echo inside its userdata, moved here so it is a
# file in the repository rather than a string in a shell script. Three changes, all on lines that could not
# have worked as written:
#
#   - The bucket and key come from the environment, not from a bucket name Terraform interpolated into the
#     Python source. The function's configuration now owns them, so a renamed bucket is a configuration
#     change rather than a rebuilt image.
#   - The error path returned json.dumps(e). An exception is not JSON-serialisable, so that line raised a
#     TypeError of its own and the original error was lost; it is str(e) now.
#   - requests.get has a timeout. Without one a stalled connection runs until Lambda's own timeout kills the
#     invocation, and the log then shows a timeout rather than which call hung.
import json
import os

import boto3
import requests

s3 = boto3.client("s3")

BUCKET_NAME = os.environ["BUCKET_NAME"]
OBJECT_KEY = os.environ.get("OBJECT_KEY", "cat.html")
SOURCE_URL = os.environ.get("SOURCE_URL", "https://cataas.com/cat?html=true")
REQUEST_TIMEOUT_SECONDS = float(os.environ.get("REQUEST_TIMEOUT_SECONDS", "10"))


def lambda_handler(event, context):
    try:
        response = requests.get(SOURCE_URL, timeout=REQUEST_TIMEOUT_SECONDS)
        response.raise_for_status()
        s3.put_object(Bucket=BUCKET_NAME, Key=OBJECT_KEY, Body=response.text, ContentType="text/html")
        return {
            "statusCode": 200,
            "body": json.dumps("Success"),
        }
    except Exception as e:
        return {
            "statusCode": 500,
            "body": json.dumps(str(e)),
        }
