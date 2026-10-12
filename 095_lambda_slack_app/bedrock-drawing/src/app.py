import logging
import os
import re

from slack_bolt import App
from slack_bolt.adapter.aws_lambda import SlackRequestHandler
from slack_bolt.adapter.aws_lambda.lambda_s3_oauth_flow import LambdaS3OAuthFlow
from slack_bolt.oauth.oauth_settings import OAuthSettings

import task

logger = logging.getLogger(__name__)

SLACK_CLIENT_ID = os.environ["SLACK_CLIENT_ID"]
SLACK_CLIENT_SECRET = os.environ["SLACK_CLIENT_SECRET"]
SLACK_SIGNING_SECRET = os.environ["SLACK_SIGNING_SECRET"]
OAUTH_STATE_S3_BUCKET_NAME = os.environ["OAUTH_STATE_S3_BUCKET_NAME"]
INSTALLATION_S3_BUCKET_NAME = os.environ["INSTALLATION_S3_BUCKET_NAME"]
TEXT_TO_IMAGE_S3_BUCKET_NAME = os.environ["TEXT_TO_IMAGE_S3_BUCKET_NAME"]
AWS_REGION_NAME = os.environ["AWS_REGION_NAME"]

app = App(
    process_before_response=True,
    raise_error_for_unhandled_request=True,
    signing_secret=SLACK_SIGNING_SECRET,
    oauth_flow=LambdaS3OAuthFlow(
        settings=OAuthSettings(
            client_id=SLACK_CLIENT_ID,
            client_secret=SLACK_CLIENT_SECRET,
            scopes=[
                "chat:write",
                "app_mentions:read",
            ],
        ),
        oauth_state_bucket_name=OAUTH_STATE_S3_BUCKET_NAME,
        installation_bucket_name=INSTALLATION_S3_BUCKET_NAME,
    ),
)


def acknowledge_app_mention(ack):
    ack()


def extract_mention_text(event, context):
    text = event.get("text", "")
    bot_user_id = context.get("bot_user_id")
    if bot_user_id:
        text = re.sub(rf"<@{re.escape(bot_user_id)}>\s*", "", text, count=1)
    return text.strip()


def handle_app_mention(say, event, context):
    thread_ts = event.get("thread_ts") or event.get("ts")

    try:
        text_input = extract_mention_text(event, context)
        if not text_input:
            say(text="멘션 뒤에 그릴 내용을 입력해 주세요.", thread_ts=thread_ts)
            return

        image_key = task.handler(text_input)
        image_url = (
            f"https://{TEXT_TO_IMAGE_S3_BUCKET_NAME}.s3.{AWS_REGION_NAME}.amazonaws.com/"
            f"{image_key}"
        )
        say(
            text="이미지를 생성했습니다.",
            blocks=[
                {
                    "type": "image",
                    "image_url": image_url,
                    "alt_text": "생성된 이미지",
                }
            ],
            thread_ts=thread_ts,
        )
    except Exception:
        logger.exception("Failed to process a Bedrock drawing mention")
        try:
            say(
                text="이미지를 생성하는 중 오류가 발생했습니다. 잠시 후 다시 시도해 주세요.",
                thread_ts=thread_ts,
            )
        except Exception:
            logger.exception("Failed to post the Slack error reply")


app.event("app_mention")(
    ack=acknowledge_app_mention,
    lazy=[handle_app_mention],
)


def lambda_handler(event, context):
    slack_handler = SlackRequestHandler(app=app)
    return slack_handler.handle(event, context)
