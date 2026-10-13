import base64
import binascii
import json
import os
import random
from datetime import datetime, timezone

import boto3
import requests

TEXT_TO_IMAGE_S3_BUCKET_NAME = os.environ["TEXT_TO_IMAGE_S3_BUCKET_NAME"]
S3_REGION = os.environ["AWS_REGION_NAME"]
MODEL_ID = os.environ["BEDROCK_MODEL_ID"]
BEDROCK_REGION = os.environ["BEDROCK_REGION"]

translate = boto3.client("translate")
bedrock = boto3.client("bedrock-runtime", region_name=BEDROCK_REGION)
s3 = boto3.client("s3")


def lambda_handler(event, context):
    text_input = event["text_input"]
    callback_url = event["callback_url"]

    english_text = translate.translate_text(
        Text=text_input,
        SourceLanguageCode="ko",
        TargetLanguageCode="en",
    )["TranslatedText"]

    # Stable Image Core uses a different native payload and response from the retired SDXL model.
    # https://docs.aws.amazon.com/bedrock/latest/userguide/bedrock-runtime_example_bedrock-runtime_InvokeModel_StableDiffusion_section.html
    seed = random.randint(0, 4294967294)
    response = bedrock.invoke_model(
        modelId=MODEL_ID,
        contentType="application/json",
        accept="application/json",
        body=json.dumps(
            {
                "prompt": english_text,
                "aspect_ratio": "1:1",
                "output_format": "png",
                "seed": seed,
            }
        ),
    )
    model_response = json.loads(response["body"].read())

    finish_reasons = model_response.get("finish_reasons") or []
    if finish_reasons and finish_reasons[0] is not None:
        raise RuntimeError(
            f"Stable Image Core did not generate an image: {finish_reasons[0]}"
        )

    images = model_response.get("images") or []
    if not images or not images[0]:
        raise RuntimeError("Stable Image Core response did not include images[0].")

    try:
        image_data = base64.b64decode(images[0], validate=True)
    except (binascii.Error, ValueError, TypeError) as error:
        raise RuntimeError(
            "Stable Image Core returned invalid base64 image data."
        ) from error

    image_name = f"{datetime.now(timezone.utc):%Y%m%d%H%M%S}_{seed}.png"
    s3.put_object(
        Bucket=TEXT_TO_IMAGE_S3_BUCKET_NAME,
        Key=image_name,
        Body=image_data,
        ContentType="image/png",
    )
    image_url = (
        f"https://{TEXT_TO_IMAGE_S3_BUCKET_NAME}.s3.{S3_REGION}.amazonaws.com/"
        f"{image_name}"
    )

    # https://kakaobusiness.gitbook.io/main/tool/chatbot/skill_guide/ai_chatbot_callback_guide#skillresponse
    requests.post(
        callback_url,
        json={
            "version": "2.0",
            "useCallback": False,
            "template": {
                "outputs": [
                    {
                        "simpleImage": {
                            "imageUrl": image_url,
                            "altText": "text-to-image",
                        }
                    }
                ]
            },
        },
    )

    return True
