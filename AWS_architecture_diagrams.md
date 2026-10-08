# AWS構成図

この資料は、各課題の `README.md` と `infra/terraform/main.tf` から作成した構成図です。
Mermaid対応のMarkdownビューア、GitHub、VS Code拡張などで図として表示できます。

draw.io版は `AWS_architecture_diagrams.drawio` にあります。

## 課題1: CloudFront + ALB + ECS Fargate + RDS

```mermaid
flowchart TB
  client["Client / Browser"]
  github["GitHub Actions<br/>build / push / deploy"]

  subgraph aws["AWS account"]
    cf["CloudFront Distribution<br/>HTTPS redirect / default cert"]
    ecr["ECR Repository<br/>FastAPI container image"]
    logs["CloudWatch Logs<br/>/ecs/{project}-api"]
    ecsRole["IAM Role<br/>ECS task execution"]

    subgraph vpc["VPC 10.10.0.0/16"]
      igw["Internet Gateway"]

      subgraph public["Public subnets x2"]
        alb["Application Load Balancer<br/>HTTP :80"]
        nat["NAT Gateway<br/>private egress"]
        bastion["Bastion EC2<br/>migration host"]
      end

      subgraph private["Private subnets x2"]
        ecs["ECS Fargate Service<br/>FastAPI :8000"]
        rds["RDS PostgreSQL 16<br/>tasks DB"]
      end
    end
  end

  client -->|"HTTPS"| cf
  cf -->|"HTTP origin"| alb
  alb -->|"Target group :8000"| ecs
  ecs -->|"DATABASE_URL / TCP :5432"| rds

  github -->|"docker push"| ecr
  github -->|"update task definition<br/>deploy service"| ecs
  ecs -->|"pull image"| ecr
  ecs -->|"awslogs"| logs
  ecsRole -.->|"execution role"| ecs

  ecs -->|"outbound via private route"| nat
  nat --> igw
  bastion -->|"psql migration / TCP :5432"| rds
  client -.->|"SSH from allowed_ssh_cidr / TCP :22"| bastion
```

### 課題1の通信と境界

| 区分 | 内容 |
| --- | --- |
| 外部入口 | Client -> CloudFront -> ALB |
| アプリ実行 | ECS Fargateがprivate subnetでFastAPIコンテナを実行 |
| データベース | RDS PostgreSQLはprivate subnetに配置し、public accessなし |
| デプロイ | GitHub ActionsでDocker build、ECR push、ECS service deploy |
| ログ | ECSコンテナログをCloudWatch Logsへ送信 |
| DB migration | Bastion EC2からRDSへ `psql` でmigrationを実行 |

### 課題1のSecurity Group

| Security Group | Ingress | Egress |
| --- | --- | --- |
| ALB | `0.0.0.0/0` から TCP `80` | 全許可 |
| ECS | ALB SG から TCP `8000` | 全許可 |
| RDS | ECS SG と Bastion SG から TCP `5432` | Terraform上は未定義 |
| Bastion | `allowed_ssh_cidr` から TCP `22` | 全許可 |

現状のTerraformでは、ALBはCloudFrontからのみに制限せず `0.0.0.0/0` からHTTPを受けます。
本番寄りにする場合は、CloudFront managed prefix list、独自ヘッダー検証、またはWAFなどで入口制御を強化します。

## 課題2: EventBridge + Step Functions + Lambda + Slack通知

```mermaid
flowchart LR
  subgraph aws["AWS account"]
    rule["EventBridge Rule<br/>rate(1 day)"]
    eventRole["IAM Role<br/>events.amazonaws.com"]
    sfn["Step Functions<br/>notify-slack state machine"]
    sfnRole["IAM Role<br/>states.amazonaws.com"]
    lambda["Lambda<br/>Python 3.12 notify-slack"]
    lambdaRole["IAM Role<br/>lambda.amazonaws.com"]
    ssm["SSM Parameter Store<br/>SecureString webhook URL"]
    logs2["CloudWatch Logs<br/>Lambda execution logs"]
  end

  slack["Slack Incoming Webhook"]

  rule -->|"scheduled JSON input"| sfn
  sfn -->|"InvokeFunction"| lambda
  lambda -->|"GetParameter"| ssm
  lambda -->|"POST message"| slack
  lambda -->|"execution logs"| logs2

  rule -.->|"assumes"| eventRole
  eventRole -.->|"states:StartExecution"| sfn
  sfn -.->|"assumes"| sfnRole
  sfnRole -.->|"lambda:InvokeFunction"| lambda
  lambda -.->|"assumes"| lambdaRole
  lambdaRole -.->|"ssm:GetParameter"| ssm
```

### 課題2の処理フロー

| Step | 内容 |
| --- | --- |
| 1 | EventBridge Ruleがスケジュールに従ってイベントを発火 |
| 2 | EventBridgeのIAM RoleでStep Functions実行を開始 |
| 3 | Step FunctionsがLambdaを呼び出す |
| 4 | LambdaがSSM Parameter StoreからSlack Webhook URLを取得 |
| 5 | LambdaがSlack Incoming Webhookへ通知をPOST |
| 6 | Lambdaの実行ログはCloudWatch Logsへ出力 |

### 課題2のSecret管理

Slack Webhook URLは `aws_ssm_parameter` の `SecureString` として保存され、LambdaにはParameter名だけを環境変数で渡します。
ただしTerraform stateにはsensitive値が残るため、学習後のstate保管先とアクセス権限にも注意が必要です。
