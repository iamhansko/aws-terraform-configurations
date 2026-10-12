"""Returns a presigned GET URL for one S3 object.

Invoked directly by Terraform's aws_lambda_invocation, so the event is the invocation's input JSON and the
return value is what Terraform stores as the result. There is no cfnresponse here: the _monolithic source
for this function was a CloudFormation custom resource handler, and it could not run as one either - the
file held the Python repr of a {'Fn::Sub': ...} dict rather than Python.

The URL is signed with this function's role session, which is the subject of the demo. A presigned URL
stops working at whichever comes first: ExpiresIn, or the expiry of the temporary credentials that signed it.
"""
import os

import boto3
from botocore.config import Config

REGION = os.environ["AWS_REGION"]

# The regional endpoint with virtual-hosted addressing, so the URL is
# https://<bucket>.s3.<region>.amazonaws.com/<key> - the form CloudFormation's --template-url accepts and the
# one that does not depend on a redirect from the global endpoint.
s3 = boto3.client(
    "s3",
    region_name=REGION,
    endpoint_url=f"https://s3.{REGION}.amazonaws.com",
    config=Config(signature_version="s3v4", s3={"addressing_style": "virtual"}),
)


def handler(event, context):
    expires_in = int(event["ExpiresIn"])
    url = s3.generate_presigned_url(
        ClientMethod="get_object",
        Params={"Bucket": event["S3Bucket"], "Key": event["S3ObjectKey"]},
        ExpiresIn=expires_in,
    )
    return {"Url": url, "ExpiresIn": expires_in}
