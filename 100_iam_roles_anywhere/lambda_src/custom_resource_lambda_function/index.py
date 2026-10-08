"""Waits for the certificate export to reach S3, then terminates the export instance.

What was here before: the literal CloudFormation intrinsic the conversion emitted,

    {'Fn::Sub': 'import boto3\\nimport cfnresponse\\n...'}

which is a dict expression at module level. Python parses it, the module imports cleanly, and it
defines nothing - so Lambda answers every invocation with

    Runtime.HandlerNotFound: Handler 'lambda_handler' missing on module 'index'

Three things about the body inside that Fn::Sub had to change rather than simply being unwrapped.

cfnresponse is gone. It exists only inside Lambda functions CloudFormation builds from inline ZipFile
code, and only a custom resource has a ResponseURL to post to. Importing it here raises ImportError,
and nothing is waiting for that protocol: aws_lambda_invocation reads the return value, and an
exception fails the apply.

The instance id comes from the event. The template interpolated ${BastionEc2.InstanceId} into the
source at deploy time, which Terraform cannot do to a file that archive_file zips - and baking a
resource attribute into the function's code would rebuild the deployment package every time the
instance changed. The caller passes it as input instead.

And the function waits before it terminates. In the template, the instance's CreationPolicy held
this custom resource back until cfn-signal arrived. The conversion replaced that with an SSM
association, and the association's wait does not hold: its status read Success before SSM had sent
the command, and an updated association is not waited on at all - so this function terminated the
instance seconds after launch and the bucket stayed empty (the root main.tf has the timeline). The
wait lives here because this is the destructive step: the bucket is listed until every exported
object is there and newer than the instance's launch, and only then is TerminateInstances called.
No object is ever read - listing is enough to see the upload finished, and one of them is an
unencrypted private key.
"""

import json
import time

import boto3
from botocore.exceptions import BotoCoreError, ClientError

POLL_SECONDS = 15
# Held back from the function's own timeout for the terminate call and the return. Without it a slow
# bootstrap ends in Lambda's bare "Task timed out after N seconds", which names neither the objects
# that are missing nor the instance to look at.
RESERVE_MILLIS = 30_000
LIVE_STATES = ("pending", "running")


def lambda_handler(event, context):
    print(json.dumps(event))

    instance_ids = event.get("instance_ids") or []
    if not instance_ids:
        # Raising rather than returning quietly. An empty list terminates nothing, and a silent
        # success here leaves a running instance holding the exported private key - which is the
        # one outcome this function exists to prevent.
        raise ValueError("event must carry a non-empty instance_ids list")

    export = event.get("wait_for_export") or {}
    bucket = export.get("bucket")
    keys = export.get("keys") or []
    if not bucket or not keys:
        # Required rather than optional: terminating without it is exactly the race this function
        # was changed to close.
        raise ValueError("event must carry wait_for_export with a bucket and a non-empty keys list")

    ec2 = boto3.client("ec2")
    started = time.monotonic()
    verified = _wait_for_export(ec2, boto3.client("s3"), instance_ids, bucket, keys, context)
    waited_seconds = round(time.monotonic() - started)
    print(f"export verified after {waited_seconds}s: {json.dumps(verified)}")

    response = ec2.terminate_instances(InstanceIds=instance_ids)

    # Returned so the state of the invocation records what was verified and what was shut down. The
    # call is asynchronous: the instances report shutting-down here and reach terminated a little
    # later.
    return {
        "waited_seconds": waited_seconds,
        "verified_objects": verified,
        "terminating": [
            {
                "instance_id": change["InstanceId"],
                "previous_state": change["PreviousState"]["Name"],
                "current_state": change["CurrentState"]["Name"],
            }
            for change in response["TerminatingInstances"]
        ],
    }


def _wait_for_export(ec2, s3, instance_ids, bucket, keys, context):
    """Returns {key: last_modified} once every key is in the bucket and newer than the launch."""
    missing = list(keys)
    launched = None
    last_error = None
    while True:
        try:
            launched = _launch_time_of_running(ec2, instance_ids, bucket, missing)
            if launched is not None:
                # Every apply after the first replaces the instance and exports again, so the
                # bucket can already hold an earlier instance's objects. Only objects written after
                # this instance launched prove that this one finished.
                listing = s3.list_objects_v2(Bucket=bucket)
                modified = {obj["Key"]: obj["LastModified"] for obj in listing.get("Contents", [])}
                missing = [key for key in keys if key not in modified or modified[key] < launched]
                if not missing:
                    return {key: modified[key].isoformat() for key in keys}
                print(f"waiting for {missing} in s3://{bucket}")
            last_error = None
        except (ClientError, BotoCoreError) as error:
            # Retried rather than raised. Right after launch DescribeInstances can still answer
            # InvalidInstanceID.NotFound, and a role policy changed in the same apply can take a few
            # seconds to reach this function. A permanent error still ends the wait, at the
            # deadline below, with this message attached.
            last_error = error
            print(f"retrying after {error}")

        if context.get_remaining_time_in_millis() < RESERVE_MILLIS + POLL_SECONDS * 1000:
            raise TimeoutError(_timeout_message(instance_ids, bucket, missing, launched, last_error))
        time.sleep(POLL_SECONDS)


def _launch_time_of_running(ec2, instance_ids, bucket, missing):
    """The earliest launch time, or None while EC2 does not list every instance yet."""
    instances = [
        instance
        for reservation in ec2.describe_instances(InstanceIds=instance_ids)["Reservations"]
        for instance in reservation["Instances"]
    ]
    if len(instances) < len(instance_ids):
        print(f"EC2 lists {len(instances)} of {len(instance_ids)} instances so far")
        return None
    # An instance that is no longer running will never finish the export, so waiting out the
    # timeout would only delay the same failure.
    gone = {i["InstanceId"]: i["State"]["Name"] for i in instances if i["State"]["Name"] not in LIVE_STATES}
    if gone:
        raise RuntimeError(
            f"the export instance stopped running before s3://{bucket} held every exported object:"
            f" {gone}; still missing {missing}"
        )
    return min(i["LaunchTime"] for i in instances)


def _timeout_message(instance_ids, bucket, missing, launched, last_error):
    message = (
        f"the certificate export did not reach s3://{bucket} before this function's timeout."
        f" Still missing: {missing}"
        + (f" (objects older than the launch at {launched.isoformat()} do not count)" if launched else "")
        + f". {', '.join(instance_ids)} is left running. If its bootstrap is only slow, running"
        " terraform apply again waits again and terminates it once the objects are there. If the"
        " bootstrap failed, its log is in"
        f" aws ec2 get-console-output --instance-id {instance_ids[0]} --latest --output text,"
        " and because cloud-init runs the bootstrap only once, re-run it after the fix with"
        " terraform apply -replace=module.certificate_export_ec2.aws_instance.certificate_export_ec2"
    )
    if last_error is not None:
        message += f". Last AWS error: {last_error}"
    return message
