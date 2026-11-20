# Outputs that embed the AWS account ID (ARNs, ECR URL) are marked sensitive so
# they never print during a recorded `terraform apply`.

output "region" {
  value = var.region
}

output "cluster_name" {
  value = module.eks.cluster_name
}

output "cluster_version" {
  value = module.eks.cluster_version
}

output "ecr_repository_name" {
  value = module.ecr.repository_name
}

output "ecr_repository_url" {
  value     = module.ecr.repository_url
  sensitive = true
}

output "rds_address" {
  value = module.rds.address
}

output "ssm_app_config_path" {
  value = local.ssm_app_path
}

output "github_deploy_role_arn" {
  description = "Store as GitHub secret AWS_DEPLOY_ROLE_ARN."
  value       = module.github_oidc.deploy_role_arn
  sensitive   = true
}

output "github_terraform_role_arn" {
  description = "Store as GitHub secret AWS_TERRAFORM_ROLE_ARN."
  value       = module.github_oidc.terraform_role_arn
  sensitive   = true
}

output "configure_kubectl" {
  value = "aws eks update-kubeconfig --name ${module.eks.cluster_name} --region ${var.region}"
}
