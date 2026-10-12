import base64
import binascii
import json
import os
import random
from datetime import datetime, timezone

import boto3

TEXT_TO_IMAGE_S3_BUCKET_NAME = os.environ["TEXT_TO_IMAGE_S3_BUCKET_NAME"]
MODEL_ID = os.environ["BEDROCK_MODEL_ID"]
BEDROCK_REGION = os.environ["BEDROCK_REGION"]

translate = boto3.client("translate")
bedrock = boto3.client("bedrock-runtime", region_name=BEDROCK_REGION)
s3 = boto3.client("s3")


def handler(text_input):
    english_text = translate.translate_text(
        Text=text_input,
        SourceLanguageCode="ko",
        TargetLanguageCode="en",
    )["TranslatedText"]

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

    image_key = f"{datetime.now(timezone.utc):%Y%m%d%H%M%S}_{seed}.png"
    s3.put_object(
        Bucket=TEXT_TO_IMAGE_S3_BUCKET_NAME,
        Key=image_key,
        Body=image_data,
        ContentType="image/png",
    )

    return image_key
