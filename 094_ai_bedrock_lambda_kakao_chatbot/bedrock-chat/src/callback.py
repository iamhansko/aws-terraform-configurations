import json
import os

import boto3
import requests

# Terraform keeps the regional Lambda/API resources where they are, but points the Bedrock client at the
# source Region that the account's SCP permits. The model and Region are a tested pair and are required rather
# than silently falling back to a model or endpoint that can be denied or retired.
MODEL_ID = os.environ["BEDROCK_MODEL_ID"]
BEDROCK_REGION = os.environ["BEDROCK_REGION"]
bedrock = boto3.client("bedrock-runtime", region_name=BEDROCK_REGION)


# https://docs.aws.amazon.com/bedrock/latest/userguide/model-parameters-anthropic-claude-messages.html
def bedrock_chatbot(text):
    response = bedrock.invoke_model(
        modelId=MODEL_ID,
        body=json.dumps(
            {
                "anthropic_version": "bedrock-2023-05-31",
                "messages": [{"role": "user", "content": text}],
                "max_tokens": 2048,
                "temperature": 0.5,
            }
        ),
        accept="application/json",
        contentType="application/json",
    )
    return json.loads(response.get("body").read())["content"][0]["text"]


def lambda_handler(event, context):
    text_input = event["text_input"]
    callback_url = event["callback_url"]

    result = bedrock_chatbot(text_input)

    # https://kakaobusiness.gitbook.io/main/tool/chatbot/skill_guide/ai_chatbot_callback_guide#skillresponse
    requests.post(
        callback_url,
        json={
            "version": "2.0",
            "useCallback": False,
            "template": {"outputs": [{"simpleText": {"text": f"{result}"}}]},
        },
    )

    return True
