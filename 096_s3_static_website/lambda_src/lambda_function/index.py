# The escape-room game's backend, behind a public Lambda function URL. It answers one question: what is
# the password.
#
# This file was not Python when the conversion produced it. Byte for byte, it held:
#
#     {'Fn::Sub': 'import json\ndef lambda_handler(event, context):\n  password = "${GamePassword}"\n  return {\n    "statusCode": 200,\n    "body": json.dumps({"password": password})\n  }\n'}
#
# That is the repr of the CloudFormation Fn::Sub node the template carried inline as ZipFile. tools/cfn2tf
# wrote the node out instead of unwrapping it, and what it left behind is a file that imports perfectly - a
# dict literal is a valid expression statement - and defines no lambda_handler at all. Every request would
# have failed with "Handler 'lambda_handler' missing on module 'index'": at runtime, in the function's log,
# with terraform validate, plan and apply all reporting success and the browser seeing only a failed fetch.
#
# The placeholder is the second half of the same defect. Fn::Sub would have substituted the stack's
# GamePassword parameter into the source; Terraform has no equivalent, and the conversion dropped the
# substitution without dropping the placeholder. So even unwrapped, this function would have served the
# literal characters ${GamePassword} to the page as the password - and the converted root declared a
# game_password variable that nothing referenced, which is the trace that was left of it.
#
# The value now arrives as an environment variable, which is a substitution Terraform can perform. See
# game_password and game_password_environment_variable in the root's variables.tf.
import json
import os

# Read at import, not per request. A missing variable is then a cold-start error that appears once in the
# log with a clear message, rather than a KeyError on every request that the browser reports as an opaque
# network failure. The name has to match game_password_environment_variable in the root: those two are
# load-bearing together, and renaming one leaves the function raising on every call.
PASSWORD = os.environ["GAME_PASSWORD"]


def lambda_handler(event, context):
    # The shape a function URL in BUFFERED invoke mode expects: a dict carrying statusCode and a string
    # body. The content-type header is not in the original and is not strictly required - Lambda defaults
    # the response to application/json - but the page calls .json() on it, so saying it is cheaper than
    # relying on the default.
    return {
        "statusCode": 200,
        "headers": {"content-type": "application/json"},
        "body": json.dumps({"password": PASSWORD}),
    }
