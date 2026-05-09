output "ecr_repository_url" {
  value = aws_ecr_repository.api.repository_url
}

output "ecs_cluster_name" {
  value = aws_ecs_cluster.main.name
}

output "ecs_service_name" {
  value = aws_ecs_service.api.name
}

output "alb_dns_name" {
  value = aws_lb.api.dns_name
}

output "cloudfront_domain_name" {
  value = aws_cloudfront_distribution.api.domain_name
}

output "rds_endpoint" {
  value = aws_db_instance.postgres.address
}

output "bastion_public_ip" {
  value = aws_instance.bastion.public_ip
}
