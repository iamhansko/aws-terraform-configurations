# TOKEN authorizer for the MCP API: allows a request whose Authorization header is "Bearer <token>".
#
# Recovered from the CloudFormation template's InlineCode, which the conversion wrote as the Python repr of
# {'Fn::Sub': '...'} rather than as code. That string had no ${} substitutions and matches authorizer/app.py in
# github.com/mikegc-aws/Lambda-MCP-Server. Three things are changed, each for a reason below:
#
#   1. The expected token is read from SSM Parameter Store, not from an MCP_AUTH_TOKEN environment variable.
#   2. The token is compared in constant time.
#   3. The policy allows every method of the stage, not only the methodArn of the request being authorised.
import hmac
import os

import boto3

# The parameter holding the token, and the version Terraform wrote. The version is part of the function's
# configuration so that a new token changes the configuration, which retires every warm execution environment
# and with it the cached value below - no TTL logic is needed to pick up a rotation.
#
# The original template put the token itself in the environment ("Peccy", as a parameter default). Anyone with
# lambda:GetFunctionConfiguration reads environment variables in clear, so that is a second copy of the secret
# in a place that is not a secret store.
TOKEN_PARAMETER_NAME = os.environ['MCP_AUTH_TOKEN_PARAMETER_NAME']
TOKEN_PARAMETER_VERSION = os.environ.get('MCP_AUTH_TOKEN_PARAMETER_VERSION', '')

_ssm = boto3.client('ssm')
_expected_token = None


def _get_expected_token():
    """Read the token once per execution environment, pinned to the version in the configuration."""
    global _expected_token
    if _expected_token is None:
        name = TOKEN_PARAMETER_NAME
        if TOKEN_PARAMETER_VERSION:
            name = f'{name}:{TOKEN_PARAMETER_VERSION}'
        # A failure here is deliberately not turned into 'Unauthorized': API Gateway reports it as a 500, which
        # points at the configuration rather than at the caller's token.
        response = _ssm.get_parameter(Name=name, WithDecryption=True)
        _expected_token = response['Parameter']['Value']
    return _expected_token


def lambda_handler(event, context):
    """Lambda authorizer for API Gateway."""

    # Get the Authorization header from the event
    auth_header = event.get('authorizationToken', '')
    method_arn = event['methodArn']

    # Check if it's a Bearer token
    if not auth_header.startswith('Bearer '):
        raise Exception('Unauthorized')  # Return 401 if no valid Authorization header

    # Extract and validate token
    token = auth_header.split(' ')[1]
    expected_token = _get_expected_token()

    # compare_digest rather than !=, so the time a wrong guess takes says nothing about how much of it was right.
    if not expected_token or not hmac.compare_digest(token.encode('utf-8'), expected_token.encode('utf-8')):
        raise Exception('Unauthorized')

    # arn:aws:execute-api:<region>:<account>:<api-id>/<stage>/<method>/<path> -> .../<api-id>/<stage>/*/*
    #
    # The original allowed method_arn only. API Gateway caches this policy per token for the authorizer's TTL
    # (300 seconds here) and applies the cached copy to every method, so after a POST /mcp the same client's
    # DELETE /mcp - which is how an MCP client ends its session - was answered 403 from the cache.
    api_arn, stage = method_arn.split('/')[:2]

    # Generate the IAM policy
    return {
        'principalId': 'user',
        'policyDocument': {
            'Version': '2012-10-17',
            'Statement': [{
                'Action': 'execute-api:Invoke',
                'Effect': 'Allow',
                'Resource': f'{api_arn}/{stage}/*/*'
            }]
        }
    }
