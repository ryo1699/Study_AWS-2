output "lambda_function_name" {
  value = aws_lambda_function.notify_slack.function_name
}

output "state_machine_arn" {
  value = aws_sfn_state_machine.notify_slack.arn
}

output "eventbridge_rule_name" {
  value = aws_cloudwatch_event_rule.schedule.name
}

output "slack_webhook_parameter_name" {
  value = aws_ssm_parameter.slack_webhook_url.name
}
