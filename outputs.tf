output "flask_repo_url" {
  value       = aws_ecr_repository.flask_repo.repository_url
  description = "ECR repository URL for Flask backend"
}

output "express_repo_url" {
  value       = aws_ecr_repository.express_repo.repository_url
  description = "ECR repository URL for Express frontend"
}

output "alb_dns_name" {
  value       = aws_lb.main_lb.dns_name
  description = "DNS name of the Application Load Balancer"
}
