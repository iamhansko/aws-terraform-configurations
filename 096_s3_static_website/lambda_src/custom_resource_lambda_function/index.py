# Terminates the instance that seeded the website bucket, once it has nothing left to do.
#
# Like the backend, this file was not Python when the conversion produced it. Byte for byte, it held:
#
#     {'Fn::Sub': 'import boto3\nimport cfnresponse\ndef lambda_handler(event, context):\n  print(json.dumps(event))\n  try:\n    ec2 = boto3.client("ec2")\n    response = ec2.terminate_instances(\n      InstanceIds=["${BastionEc2.InstanceId}"]\n    )\n    cfnresponse.send(event, context, cfnresponse.SUCCESS, {})\n  except Exception as e:\n    cfnresponse.send(event, context, cfnresponse.FAILED, {"Message": str(e)})\n'}
#
# Unwrapping that is not enough, because the handler inside it could not have run under
# aws_lambda_invocation either. Four independent reasons, any one of them fatal:
#
#   1. import cfnresponse. AWS injects that module only into functions whose code was inlined in the
#      template as ZipFile. This function is packaged by archive_file, so the import raises
#      ModuleNotFoundError before the handler is entered.
#   2. json is used and never imported. print(json.dumps(event)) is the first statement in the handler and
#      it is outside the try, so it raises NameError on the first line that runs.
#   3. ${BastionEc2.InstanceId} is an unsubstituted Fn::Sub reference, the same defect the backend has. The
#      function would have asked EC2 to terminate an instance called that.
#   4. cfnresponse.send POSTs to event['ResponseURL'] and echoes event['StackId'], ['RequestId'] and
#      ['LogicalResourceId']. A CloudFormation custom resource request carries all four;
#      aws_lambda_invocation sends the input verbatim, and the converted resource sent
#      jsonencode({}) - so every one of those lookups raises KeyError.
#
# The protocol mismatch in (4) is the one that matters structurally: a custom resource handler reports its
# result by making an HTTP request and returns nothing, while aws_lambda_invocation reads the return value
# of a synchronous invoke and ignores anything the function posts elsewhere. The same defect is recorded in
# 102_windows_rdp/modules/app_secret/main.tf, where the conclusion was to drop the function entirely.
#
# Here it is kept, because terminating the seeder is a real thing to want, and rewritten against the
# resource that actually invokes it: the instance ids arrive in the payload and the result comes back as a
# return value. Whether apply calls it is a separate question - see terminate_seeder_after_seeding in the
# root, which defaults to false because terminating a managed aws_instance makes the root churn forever.
import json

import boto3


def lambda_handler(event, context):
    print(json.dumps(event))

    instance_ids = event.get("instance_ids") or []
    if not instance_ids:
        # Raise rather than return. aws_lambda_invocation treats a function error as an apply failure and a
        # returned value as success, so returning here would record a successful invocation that terminated
        # nothing - which is the converted resource's jsonencode({}) payload reaching this branch quietly.
        raise ValueError(
            'no instance_ids in the payload; expected {"instance_ids": ["i-0123456789abcdef0"]}'
        )

    ec2 = boto3.client("ec2")
    response = ec2.terminate_instances(InstanceIds=instance_ids)

    # Rebuilt rather than returned as-is. aws_lambda_invocation stores the return value as a JSON string,
    # and a boto3 response is not JSON-serialisable - it carries a ResponseMetadata block and, for some
    # calls, datetime objects that json.dumps refuses with "Object of type datetime is not JSON
    # serializable". That failure would come back as an apply error naming the function rather than the
    # response.
    return {
        "terminating": [
            {
                "instance_id": instance["InstanceId"],
                "current_state": instance["CurrentState"]["Name"],
                "previous_state": instance["PreviousState"]["Name"],
            }
            for instance in response["TerminatingInstances"]
        ]
    }
