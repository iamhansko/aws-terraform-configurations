"""Starts a Step Functions execution and returns its ARN.

This exists because Terraform has no resource for "run this state machine once": a state machine is
infrastructure, an execution is not. So the two demo executions are started through this function, invoked
by aws_lambda_invocation at apply time.

Rewritten from the version the _monolithic template carried, which could not run at all. That one imported
cfnresponse - a module CloudFormation injects into the runtime only for inline Lambda code - so this zipped
function would have failed on the import before reaching the handler. It also read its arguments out of
event["ResourceProperties"], the shape CloudFormation sends a custom resource, while the Terraform
invocation passes them at the top level. Two separate reasons the same call could never have succeeded.
"""

import json

import boto3

stepfunctions = boto3.client("stepfunctions")


def lambda_handler(event, context):
    """Start one execution.

    Expects {"stateMachineArn": "...", "input": {...}} and returns the execution's ARN and start time so
    that aws_lambda_invocation's result carries something worth reading - the whole point of starting the
    execution from Terraform rather than by hand.

    Errors are raised rather than swallowed. The CloudFormation original reported a failure back through
    cfnresponse and returned normally, which meant a stack that succeeded with nothing started; here a
    failure fails the apply, which is what a caller can act on.
    """
    print(json.dumps(event))

    state_machine_arn = event["stateMachineArn"]
    execution_input = json.dumps(event["input"])

    response = stepfunctions.start_execution(
        stateMachineArn=state_machine_arn,
        input=execution_input,
    )

    return {
        "executionArn": response["executionArn"],
        "startDate": response["startDate"].isoformat(),
        "input": json.loads(execution_input),
    }
