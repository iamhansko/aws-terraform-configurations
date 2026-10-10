"""Waits until an object the workbench uploads is in S3, and fails early if the association checking it fails.

The callers - the six Lambda functions and the GameLift build - read the object the moment they are created,
and something has to hold them until the upload has happened. The artifacts_uploaded association's own
wait_for_success_timeout_seconds does not. An association that no target has picked up yet reports
Overview.Status Success, and the provider's waiter accepts that Success and returns. On a first apply the
association is created seconds after the instance launches, so the readers ran a minute before the uploads
(the root main.tf has the CloudTrail timeline).

So the wait lives here, against the thing the readers actually need: HeadObject on the key, until it answers.
The association is consulted only for the opposite answer - an execution of its current version that has
failed - so an upload that cannot happen fails the apply within one poll, with the command that shows its
output, instead of at this function's timeout. Its Success is never trusted, for the reason above.
"""

import json
import time

import boto3
from botocore.exceptions import BotoCoreError, ClientError

POLL_SECONDS = 10
# Held back from the function's timeout so the wait ends in this function's own TimeoutError, which names the
# object and the association, rather than Lambda's bare "Task timed out after N seconds".
RESERVE_MILLIS = 15_000
# Execution statuses that end a run without the upload. Success is deliberately absent: see the docstring.
FAILED_EXECUTION_STATES = ("Failed", "TimedOut", "Cancelled")
# HeadObject has no response body, so a missing key comes back as the bare status code. It is 404 only
# because the role may list the bucket - without s3:ListBucket, S3 answers 403 for a key that does not exist,
# which would read as a permissions problem for the whole wait.
MISSING_CODES = ("404", "NoSuchKey", "NotFound")


def lambda_handler(event, context):
    print(json.dumps(event))
    bucket = event.get("bucket")
    key = event.get("key")
    association_id = event.get("association_id")
    if not bucket or not key or not association_id:
        raise ValueError("event must carry bucket, key and association_id")

    s3 = boto3.client("s3")
    ssm = boto3.client("ssm")
    started = time.monotonic()
    last_error = None

    while True:
        try:
            head = s3.head_object(Bucket=bucket, Key=key)
            waited_seconds = round(time.monotonic() - started)
            print(f"s3://{bucket}/{key} found after {waited_seconds}s")
            # bucket and key are echoed back so the callers can name the object through this result, which is
            # what orders them after this function. The rest is for the invocation's record only: this result
            # is fixed at the first invoke, while the workbench replaces the object whenever its upload is run
            # again.
            return {
                "bucket": bucket,
                "key": key,
                "content_length": head.get("ContentLength"),
                "last_modified": head["LastModified"].isoformat(),
                "waited_seconds": waited_seconds,
            }
        except ClientError as error:
            if error.response.get("Error", {}).get("Code") in MISSING_CODES:
                last_error = None
                print(f"waiting for s3://{bucket}/{key}")
            else:
                # Retried rather than raised: a role policy created in the same apply can take a few seconds to
                # reach this function. A permanent error still ends the wait, at the deadline below, with this
                # message attached.
                last_error = error
                print(f"retrying after {error}")
        except BotoCoreError as error:
            last_error = error
            print(f"retrying after {error}")

        failure = _failed_execution(ssm, association_id)
        if failure is not None:
            raise RuntimeError(_failure_message(bucket, key, association_id, failure))

        if context.get_remaining_time_in_millis() < RESERVE_MILLIS + POLL_SECONDS * 1000:
            raise TimeoutError(_timeout_message(bucket, key, association_id, last_error))
        time.sleep(POLL_SECONDS)


def _failed_execution(ssm, association_id):
    """The newest execution of the association's current version if it has failed, otherwise None.

    Only the current version, because the association is updated in place when its commands change, and until
    the new version's run starts the newest execution is the previous version's - which can be the very failure
    the update is meant to fix.
    """
    try:
        description = ssm.describe_association(AssociationId=association_id)["AssociationDescription"]
        version = description.get("AssociationVersion")
        executions = []
        kwargs = {"AssociationId": association_id}
        while True:
            page = ssm.describe_association_executions(**kwargs)
            executions.extend(page.get("AssociationExecutions", []))
            if not page.get("NextToken"):
                break
            kwargs["NextToken"] = page["NextToken"]
    except (ClientError, BotoCoreError) as error:
        # Not fatal. Without these calls the function still waits on S3; it only loses the early exit.
        print(f"could not read the association's executions, waiting on S3 alone: {error}")
        return None

    current = [e for e in executions if e.get("AssociationVersion") == version]
    if not current:
        return None
    latest = max(current, key=lambda e: e["CreatedTime"])
    if latest.get("Status") not in FAILED_EXECUTION_STATES:
        return None

    try:
        targets = ssm.describe_association_execution_targets(
            AssociationId=association_id, ExecutionId=latest["ExecutionId"]
        ).get("AssociationExecutionTargets", [])
    except (ClientError, BotoCoreError) as error:
        # The failure is known either way; only the pointer to its output is lost.
        print(f"could not read the failed execution's targets: {error}")
        targets = []
    return {"execution": latest, "targets": targets}


def _failure_message(bucket, key, association_id, failure):
    execution = failure["execution"]
    parts = [
        f"SSM association {association_id} failed (execution {execution['ExecutionId']}:"
        f" {execution.get('Status')}/{execution.get('DetailedStatus')}) before s3://{bucket}/{key} existed,"
        " so there is nothing to wait for."
    ]
    for target in failure["targets"]:
        command_id = (target.get("OutputSource") or {}).get("OutputSourceId")
        if command_id:
            parts.append(
                f"Its output on {target['ResourceId']}: aws ssm get-command-invocation --command-id {command_id}"
                f" --instance-id {target['ResourceId']} --query '[StatusDetails,StandardErrorContent]' --output text."
                " That names the bootstrap or the upload; /var/log/cloud-init-output.log on the instance has the"
                " step that stopped."
            )
    parts.append(
        "Once the cause is fixed and the object is uploaded, re-run the association with aws ssm"
        f" start-associations-once --association-ids {association_id} - the next stage on the workbench waits"
        " for the marker it leaves - and run terraform apply again, which finds the object at its first poll."
    )
    return " ".join(parts)


def _timeout_message(bucket, key, association_id, last_error):
    message = (
        f"s3://{bucket}/{key} did not appear before this function's timeout, and association {association_id}"
        " has not failed either. aws ssm describe-association-executions --association-id"
        f" {association_id} shows which case this is. An execution still InProgress means the workbench"
        " bootstrap is only slow, and running terraform apply again waits again. Success with"
        " ResourceCountByStatus empty means the instance never picked the association up. Success with the"
        " instance counted means the association did find the object, so the difference is on this function's"
        " side - the last AWS error, if there is one, says what."
    )
    if last_error is not None:
        message += f" Last AWS error: {last_error}"
    return message
