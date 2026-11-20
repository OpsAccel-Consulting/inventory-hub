output "repository_name" {
  value = aws_ecr_repository.this.name
}

output "repository_arn" {
  value = aws_ecr_repository.this.arn
}

output "repository_url" {
  description = "Contains the account ID - keep out of committed files and screen recordings."
  value       = aws_ecr_repository.this.repository_url
  sensitive   = true
}
