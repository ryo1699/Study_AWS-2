# 課題2: EventBridge + Step Functions + Lambda + Slack通知

EventBridgeのスケジュールイベントをStep Functionsへ渡し、Step FunctionsからLambdaを呼び出してSlack Incoming Webhookへ通知する練習用構成です。

## 構成

```text
EventBridge schedule
  -> Step Functions state machine
  -> Lambda
  -> SSM Parameter Store SecureString
  -> Slack Incoming Webhook
```

Slack Webhook URLはコードへ直書きせず、SSM Parameter StoreのSecureStringに保存します。

## ファイル

- `lambda/lambda_function.py`: Slack通知Lambda
- `lambda/local_event.json`: テストイベント例
- `infra/terraform/`: Lambda、Step Functions、EventBridge、IAM、SSM Parameter Store

## Terraform

```bash
cd Study_AWS-2_2/infra/terraform
terraform init
terraform plan \
  -var 'slack_webhook_url=https://hooks.slack.com/services/XXX/YYY/ZZZ'
terraform apply \
  -var 'slack_webhook_url=https://hooks.slack.com/services/XXX/YYY/ZZZ'
```

Webhook URLは `terraform.tfvars` やCI secretから渡してください。`.gitignore` で `*.tfvars` は除外しています。

例:

```hcl
slack_webhook_url = "https://hooks.slack.com/services/XXX/YYY/ZZZ"
```

## Terraform stateをS3で共有する

この課題のTerraformはS3 backendを使う設定です。初回またはローカルstateからS3へ移行する場合は、state保存用S3バケットを先に作成してから `backend.hcl` を用意します。

```bash
cd Study_AWS-2_2/infra/terraform
cp backend.hcl.example backend.hcl
```

`backend.hcl` の `bucket` を自分のS3バケット名に変更します。

```hcl
bucket  = "YOUR_TERRAFORM_STATE_BUCKET"
key     = "study-aws-2/task2/terraform.tfstate"
region  = "ap-northeast-1"
encrypt = true
```

ローカルの `terraform.tfstate` をS3へ移行する場合:

```bash
terraform init -backend-config=backend.hcl -migrate-state
```

以後は同じディレクトリで通常どおり実行します。

```bash
terraform plan
terraform apply
```

## Step Functions入力例

```json
{
  "source": "study.aws.eventbridge",
  "detail-type": "StudyNotification",
  "detail": {
    "title": "課題2テスト通知",
    "message": "EventBridgeからStep Functions、Lambdaを経由してSlackへ通知する練習です。"
  }
}
```

AWSコンソールのStep Functionsから上記JSONを入力して `Start execution` すると、LambdaがSlackへ通知します。

## EventBridgeスケジュール

デフォルトは1日1回です。

```hcl
eventbridge_schedule_expression = "rate(1 day)"
```

短時間で確認したい場合:

```bash
terraform apply \
  -var 'slack_webhook_url=https://hooks.slack.com/services/XXX/YYY/ZZZ' \
  -var 'eventbridge_schedule_expression=rate(5 minutes)'
```

## Lambda単体確認

Lambdaは標準ライブラリの `urllib` とAWS SDK for Pythonを使います。AWS Lambda環境では `boto3` は利用できます。

ローカルでpayloadだけ確認する例:

```bash
cd Study_AWS-2_2/lambda
python - <<'PY'
import json
from lambda_function import build_slack_message

with open("local_event.json") as f:
    event = json.load(f)

print(json.dumps(build_slack_message(event), ensure_ascii=False, indent=2))
PY
```

実際のSlack送信はSSM Parameter StoreからWebhook URLを読むため、AWS上のLambdaまたはAWS認証済み環境で確認します。

## 注意点

- Slack Webhook URLは漏れると誰でも投稿できるため、Git管理しません。
- `slack_webhook_url` はTerraform stateにsensitive値として残るため、学習後はstate管理にも注意してください。
- 実運用では通知失敗時のリトライ、DLQ、CloudWatch Alarmを追加します。
