# 課題1: CloudFront + ALB + ECR + ECS + RDS のREST API

FastAPIでタスク管理REST APIを作り、DockerイメージをECRへpushし、ECS Fargateで動かす練習用構成です。入口はCloudFront、オリジンはALB、アプリはECS、DBはPostgreSQL on RDSです。

## 構成

```text
Client
  -> CloudFront
  -> ALB
  -> ECS Fargate / FastAPI
  -> RDS PostgreSQL

GitHub Actions
  -> docker build
  -> ECR push
  -> ECS task definition更新
  -> ECS service deploy

Bastion EC2
  -> RDS migration実行
```

## ファイル

- `openapi.yaml`: タスクCRUD API仕様
- `api/`: FastAPIサンプル、Dockerfile、migration SQL
- `infra/terraform/`: AWSリソース設計
- `.github/workflows/cd.yml`: ECR pushからECSデプロイまでのCD例

## ローカル起動

```bash
cd Study_AWS-2_1/api
python -m venv .venv
source .venv/bin/activate
pip install -r requirements.txt
uvicorn app.main:app --reload
```

確認:

```bash
curl http://localhost:8000/health
curl -X POST http://localhost:8000/api/tasks \
  -H 'Content-Type: application/json' \
  -d '{"title":"ミーティング資料を準備する","description":"月次報告会議のスライドを作成する"}'
curl http://localhost:8000/api/tasks
curl -X PUT http://localhost:8000/api/tasks/1 \
  -H 'Content-Type: application/json' \
  -d '{"title":"資料を更新する","status":"in_progress"}'
curl -X DELETE http://localhost:8000/api/tasks/1
```

## Docker

```bash
cd Study_AWS-2_1/api
docker build -t task-api .
docker run --rm -p 8000:8000 task-api
```

RDSへ接続する場合は `DATABASE_URL` を渡します。

```bash
docker run --rm -p 8000:8000 \
  -e DATABASE_URL='postgresql+psycopg://app_user:password@db-endpoint:5432/tasks' \
  task-api
```

## Terraform

```bash
cd Study_AWS-2_1/infra/terraform
terraform init
terraform plan \
  -var 'db_password=CHANGE_ME' \
  -var 'allowed_ssh_cidr=YOUR_IP/32'
terraform apply \
  -var 'db_password=CHANGE_ME' \
  -var 'allowed_ssh_cidr=YOUR_IP/32'
```

`db_password` は学習用でも直書きせず、ローカルの `terraform.tfvars` やCIのsecretで渡します。`.gitignore` で `*.tfvars` は除外しています。

## RDS migration

1. Terraform outputの `bastion_public_ip` と `rds_endpoint` を確認する。
2. 踏み台EC2へSSHする。
3. `psql` を用意する。
4. `api/migrations/001_create_tasks.sql` を踏み台へ配置して実行する。

例:

```bash
psql "postgresql://app_user:PASSWORD@RDS_ENDPOINT:5432/tasks" \
  -f 001_create_tasks.sql
```

本番寄りにするなら、踏み台はSSHではなくSSM Session Managerで接続する構成に変えると安全です。

## GitHub Actions CD

`.github/workflows/cd.yml` は次の流れです。

GitHub Actionsとして実際に動くworkflowは、リポジトリ直下の `.github/workflows/study-aws-2-1-cd.yml` です。`Study_AWS-2_1/.github/workflows/cd.yml` は、課題1フォルダ内で流れを確認しやすくするための参照用コピーです。

1. GitHub OIDCでAWS IAM Roleを引き受ける
2. Docker imageをbuild
3. ECRへpush
4. 既存ECS task definitionを取得
5. container imageだけ差し替える
6. ECS serviceへdeploy

GitHub側で以下を設定します。

- Secret: `AWS_ROLE_TO_ASSUME`
- Variables: `AWS_REGION`
- Variables: `ECR_REPOSITORY`
- Variables: `ECS_CLUSTER`
- Variables: `ECS_SERVICE`
- Variables: `ECS_TASK_DEFINITION`

## 注意点

- CloudFrontのデフォルト証明書を使う設計なので、独自ドメインを使う場合はACM証明書とalias設定を追加します。
- TerraformのECS task definitionには初期imageを入れ、実際のimage更新はGitHub Actionsで行います。
- `DATABASE_URL` にDBパスワードを入れる簡易構成です。実運用ではSecrets Managerから注入します。
