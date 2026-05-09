variable "aws_region" {
  type        = string
  description = "AWS region to deploy into."
  default     = "ap-northeast-1"
}

variable "project_name" {
  type        = string
  description = "Name prefix for AWS resources."
  default     = "study-aws-2-1"
}

variable "db_username" {
  type        = string
  description = "RDS application username."
  default     = "app_user"
}

variable "db_password" {
  type        = string
  description = "RDS application password. Use a tfvars file or CI secret."
  sensitive   = true
}

variable "container_image" {
  type        = string
  description = "Initial container image URI. GitHub Actions updates the ECS service after pushing to ECR."
  default     = "public.ecr.aws/docker/library/python:3.12-slim"
}

variable "allowed_ssh_cidr" {
  type        = string
  description = "CIDR allowed to SSH into the bastion. Replace with your own IP range."
  default     = "0.0.0.0/32"
}
