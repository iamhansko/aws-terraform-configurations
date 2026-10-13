import os

import requests
from langchain_aws import ChatBedrock

# Terraform keeps the regional Lambda/API resources where they are, but points the Bedrock client at the
# source Region that the account's SCP permits. The model and Region are a tested pair and are required rather
# than silently falling back to a model or endpoint that can be denied or retired.
MODEL_ID = os.environ["BEDROCK_MODEL_ID"]
BEDROCK_REGION = os.environ["BEDROCK_REGION"]


# https://python.langchain.com/docs/integrations/llms/bedrock/
def bedrock_chatbot(input_text):
    bedrock_llm = ChatBedrock(
        # No credentials_profile_name. The original passed "default", which makes boto3 look for a [default]
        # profile in ~/.aws/config. Lambda has none, so use its execution-role credentials instead.
        model_id=MODEL_ID,
        provider="anthropic",
        region_name=BEDROCK_REGION,
        model_kwargs={"temperature": 0.5, "max_tokens": 2048},
    )
    return bedrock_llm.invoke([("human", input_text)])


def lambda_handler(event, context):
    text_input = event["text_input"]
    callback_url = event["callback_url"]

    result = bedrock_chatbot(text_input).content

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
