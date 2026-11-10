# Role ARNs contain the account ID: marked sensitive so they don't print during
# `terraform apply` on a screen recording. Read with:
#   terraform output -raw github_deploy_role_arn
output "deploy_role_arn" {
  value     = aws_iam_role.deploy.arn
  sensitive = true
}

output "terraform_role_arn" {
  value     = aws_iam_role.terraform.arn
  sensitive = true
}

output "deploy_role_name" {
  value = aws_iam_role.deploy.name
}

output "terraform_role_name" {
  value = aws_iam_role.terraform.name
}
