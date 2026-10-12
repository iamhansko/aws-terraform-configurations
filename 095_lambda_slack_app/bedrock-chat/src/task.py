import os

import boto3

MODEL_ID = os.environ["BEDROCK_MODEL_ID"]
BEDROCK_REGION = os.environ["BEDROCK_REGION"]
bedrock = boto3.client("bedrock-runtime", region_name=BEDROCK_REGION)


def handler(text_input):
    response = bedrock.converse(
        modelId=MODEL_ID,
        messages=[{"role": "user", "content": [{"text": text_input}]}],
        inferenceConfig={"maxTokens": 512, "temperature": 0.5},
    )

    content = response.get("output", {}).get("message", {}).get("content", [])
    text_output = "".join(
        block["text"]
        for block in content
        if isinstance(block, dict) and isinstance(block.get("text"), str)
    )
    if not text_output:
        raise RuntimeError("Bedrock Converse response did not include a text content block.")

    return text_output
