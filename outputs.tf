output "backend_ip"{
    value = aws_instance.flask_backend.public_ip
}
output "frontend_ip"{
    value = aws_instance.express_frontend.public_ip
}
output "s3_bucket_name" {
  description = "S3 bucket for .env files"
  value       = aws_s3_bucket.backend_env_bucket.bucket
}