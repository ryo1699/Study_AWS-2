variable "aws_region" {
  type        = string
  description = "AWS region to deploy into."
  default     = "ap-northeast-1"
}

variable "project_name" {
  type        = string
  description = "Name prefix for AWS resources."
  default     = "study-aws-2-2"
}

variable "eventbridge_schedule_expression" {
  type        = string
  description = "EventBridge schedule expression."
  default     = "rate(1 day)"
}

variable "slack_webhook_url" {
  type        = string
  description = "Slack incoming webhook URL. Store it in tfvars or pass it from a secret."
  sensitive   = true
}
