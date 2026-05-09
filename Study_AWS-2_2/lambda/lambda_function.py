import json
import os
import urllib.request

import boto3


ssm = boto3.client("ssm")


def get_webhook_url() -> str:
    parameter_name = os.environ["SLACK_WEBHOOK_PARAMETER_NAME"]
    response = ssm.get_parameter(Name=parameter_name, WithDecryption=True)
    return response["Parameter"]["Value"]


def build_slack_message(event: dict) -> dict:
    detail = event.get("detail", {})
    title = detail.get("title", "AWS Study notification")
    message = detail.get("message", "EventBridgeからStep Functions経由で通知しました。")

    return {
        "text": f":bell: {title}\n{message}",
        "blocks": [
            {
                "type": "section",
                "text": {
                    "type": "mrkdwn",
                    "text": f"*{title}*\n{message}",
                },
            },
            {
                "type": "context",
                "elements": [
                    {
                        "type": "mrkdwn",
                        "text": f"source: `{event.get('source', 'manual')}`",
                    }
                ],
            },
        ],
    }


def post_to_slack(webhook_url: str, payload: dict) -> None:
    data = json.dumps(payload).encode("utf-8")
    request = urllib.request.Request(
        webhook_url,
        data=data,
        headers={"Content-Type": "application/json"},
        method="POST",
    )

    with urllib.request.urlopen(request, timeout=10) as response:
        if response.status >= 400:
            raise RuntimeError(f"Slack webhook failed with status {response.status}")


def lambda_handler(event, context):
    webhook_url = get_webhook_url()
    payload = build_slack_message(event)
    post_to_slack(webhook_url, payload)

    return {
        "statusCode": 200,
        "body": json.dumps({"message": "sent"}),
    }
