locals {
  name = var.project_name
}

data "archive_file" "lambda_zip" {
  type        = "zip"
  source_dir  = "${path.module}/../../lambda"
  output_path = "${path.module}/lambda.zip"
}

resource "aws_ssm_parameter" "slack_webhook_url" {
  name  = "/${local.name}/slack/webhook-url"
  type  = "SecureString"
  value = var.slack_webhook_url
}

resource "aws_iam_role" "lambda" {
  name = "${local.name}-lambda-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action = "sts:AssumeRole"
      Effect = "Allow"
      Principal = {
        Service = "lambda.amazonaws.com"
      }
    }]
  })
}

resource "aws_iam_role_policy_attachment" "lambda_basic" {
  role       = aws_iam_role.lambda.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

resource "aws_iam_role_policy" "lambda_ssm" {
  name = "${local.name}-lambda-ssm"
  role = aws_iam_role.lambda.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action   = ["ssm:GetParameter"]
      Effect   = "Allow"
      Resource = aws_ssm_parameter.slack_webhook_url.arn
    }]
  })
}

resource "aws_lambda_function" "notify_slack" {
  function_name    = "${local.name}-notify-slack"
  role             = aws_iam_role.lambda.arn
  handler          = "lambda_function.lambda_handler"
  runtime          = "python3.12"
  filename         = data.archive_file.lambda_zip.output_path
  source_code_hash = data.archive_file.lambda_zip.output_base64sha256
  timeout          = 15

  environment {
    variables = {
      SLACK_WEBHOOK_PARAMETER_NAME = aws_ssm_parameter.slack_webhook_url.name
    }
  }
}

resource "aws_iam_role" "step_functions" {
  name = "${local.name}-sfn-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action = "sts:AssumeRole"
      Effect = "Allow"
      Principal = {
        Service = "states.amazonaws.com"
      }
    }]
  })
}

resource "aws_iam_role_policy" "step_functions_lambda" {
  name = "${local.name}-sfn-lambda"
  role = aws_iam_role.step_functions.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action   = ["lambda:InvokeFunction"]
      Effect   = "Allow"
      Resource = aws_lambda_function.notify_slack.arn
    }]
  })
}

resource "aws_sfn_state_machine" "notify_slack" {
  name     = "${local.name}-notify-slack"
  role_arn = aws_iam_role.step_functions.arn

  definition = jsonencode({
    Comment = "EventBridgeから受け取ったイベントをLambdaへ渡し、Slackへ通知する"
    StartAt = "NotifySlack"
    States = {
      NotifySlack = {
        Type     = "Task"
        Resource = aws_lambda_function.notify_slack.arn
        End      = true
      }
    }
  })
}

resource "aws_iam_role" "eventbridge" {
  name = "${local.name}-eventbridge-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action = "sts:AssumeRole"
      Effect = "Allow"
      Principal = {
        Service = "events.amazonaws.com"
      }
    }]
  })
}

resource "aws_iam_role_policy" "eventbridge_sfn" {
  name = "${local.name}-eventbridge-sfn"
  role = aws_iam_role.eventbridge.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action   = ["states:StartExecution"]
      Effect   = "Allow"
      Resource = aws_sfn_state_machine.notify_slack.arn
    }]
  })
}

resource "aws_cloudwatch_event_rule" "schedule" {
  name                = "${local.name}-schedule"
  description         = "Scheduled Slack notification practice event."
  schedule_expression = var.eventbridge_schedule_expression
}

resource "aws_cloudwatch_event_target" "step_functions" {
  rule     = aws_cloudwatch_event_rule.schedule.name
  arn      = aws_sfn_state_machine.notify_slack.arn
  role_arn = aws_iam_role.eventbridge.arn

  input = jsonencode({
    source      = "study.aws.eventbridge"
    detail-type = "StudyNotification"
    detail = {
      title   = "課題2スケジュール通知"
      message = "EventBridgeからStep Functions、Lambdaを経由してSlackへ通知しました。"
    }
  })
}
