"""Waits until the image the workbench pushes is in ECR, and fails early if the association checking it fails.

The function this project exists for is created from that image, and CreateFunction resolves the tag on the
spot: an image that is not there yet fails the apply with "Source image ... does not exist", where an ECS
service would have kept retrying until the push landed. Something has to hold CreateFunction until the push
has happened, and the image_pushed association's own wait_for_success_timeout_seconds does not. An
association that no target has picked up yet reports Overview.Status Success, and the provider's waiter
accepts that Success and returns. On a first apply the association is created seconds after the instance
launches, so CreateFunction ran three minutes before the push (the root main.tf has the CloudTrail timeline).

So the wait lives here, against the thing CreateFunction actually needs: DescribeImages on the tag, until it
answers. The association is consulted only for the opposite answer - an execution of its current version that
has failed - so a build that cannot succeed fails the apply within one poll, with the command that shows its
output, instead of at this function's timeout. Its Success is never trusted, for the reason above.

Adapted from 063_gamelift_flexmatch's s3_object_waiter, which met the same failure waiting on an S3 object.
"""

import json
import time

import boto3
from botocore.exceptions import BotoCoreError, ClientError

POLL_SECONDS = 10
# Held back from the function's timeout so the wait ends in this function's own TimeoutError, which names the
# image and the association, rather than Lambda's bare "Task timed out after N seconds".
RESERVE_MILLIS = 15_000
# Execution statuses that end a run without the push. Success is deliberately absent: see the docstring.
FAILED_EXECUTION_STATES = ("Failed", "TimedOut", "Cancelled")
# What DescribeImages answers for a tag that has not been pushed yet. RepositoryNotFoundException is not here:
# Terraform creates the repository before this function, so its absence is a real error, and it is retried and
# reported at the deadline like any other.
MISSING_CODES = ("ImageNotFoundException",)


def lambda_handler(event, context):
    print(json.dumps(event))
    repository_name = event.get("repository_name")
    image_tag = event.get("image_tag")
    image_uri = event.get("image_uri")
    association_id = event.get("association_id")
    if not repository_name or not image_tag or not image_uri or not association_id:
        raise ValueError("event must carry repository_name, image_tag, image_uri and association_id")

    ecr = boto3.client("ecr")
    ssm = boto3.client("ssm")
    started = time.monotonic()
    last_error = None

    while True:
        try:
            details = ecr.describe_images(
                repositoryName=repository_name, imageIds=[{"imageTag": image_tag}]
            ).get("imageDetails", [])
            if details:
                image = details[0]
                waited_seconds = round(time.monotonic() - started)
                print(f"{image_uri} found after {waited_seconds}s: {image['imageDigest']}")
                # image_uri is echoed back so the function can be created from this result, which is what
                # orders CreateFunction after this wait. The rest is for the invocation's record only: this
                # result is fixed at the first invoke, while every rebuild on the workbench pushes over the tag.
                return {
                    "image_uri": image_uri,
                    "image_digest": image["imageDigest"],
                    "image_pushed_at": image["imagePushedAt"].isoformat(),
                    "waited_seconds": waited_seconds,
                }
            last_error = None
            print(f"waiting for {image_uri}")
        except ClientError as error:
            if error.response.get("Error", {}).get("Code") in MISSING_CODES:
                last_error = None
                print(f"waiting for {image_uri}")
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
            raise RuntimeError(_failure_message(image_uri, association_id, failure))

        if context.get_remaining_time_in_millis() < RESERVE_MILLIS + POLL_SECONDS * 1000:
            raise TimeoutError(_timeout_message(image_uri, association_id, last_error))
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
        # Not fatal. Without these calls the function still waits on ECR; it only loses the early exit.
        print(f"could not read the association's executions, waiting on ECR alone: {error}")
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


def _failure_message(image_uri, association_id, failure):
    execution = failure["execution"]
    parts = [
        f"SSM association {association_id} failed (execution {execution['ExecutionId']}:"
        f" {execution.get('Status')}/{execution.get('DetailedStatus')}) before {image_uri} existed,"
        " so there is no image to wait for."
    ]
    for target in failure["targets"]:
        command_id = (target.get("OutputSource") or {}).get("OutputSourceId")
        if command_id:
            parts.append(
                f"Its output on {target['ResourceId']}: aws ssm get-command-invocation --command-id {command_id}"
                f" --instance-id {target['ResourceId']} --query '[StatusDetails,StandardErrorContent]' --output text."
                " That says whether the bootstrap or the push stopped; /var/log/cloud-init-output.log on the"
                " instance has the step."
            )
    parts.append(
        "Once the cause is fixed and the image is pushed, re-run the association with aws ssm"
        f" start-associations-once --association-ids {association_id} - the README stage on the workbench waits"
        " for the marker it leaves - and run terraform apply again, which finds the image at its first poll."
    )
    return " ".join(parts)


def _timeout_message(image_uri, association_id, last_error):
    message = (
        f"{image_uri} did not appear before this function's timeout, and association {association_id}"
        " has not failed either. aws ssm describe-association-executions --association-id"
        f" {association_id} shows which case this is. An execution still InProgress means the workbench"
        " bootstrap is only slow, and running terraform apply again waits again. Success with"
        " ResourceCountByStatus empty means the instance never picked the association up. Success with the"
        " instance counted means the association did find the image, so the difference is on this function's"
        " side - the last AWS error, if there is one, says what."
    )
    if last_error is not None:
        message += f" Last AWS error: {last_error}"
    return message
