variable "name_prefix" {
  type = string
}

variable "github_org" {
  description = "GitHub organisation or user that owns the repository."
  type        = string
}

variable "github_repo" {
  description = "Repository name (without the org)."
  type        = string
}

variable "create_oidc_provider" {
  description = "Set false if the account already has the GitHub OIDC provider."
  type        = bool
  default     = true
}

variable "deploy_subjects" {
  description = "OIDC 'sub' suffixes allowed to assume the deploy role (build job on main + dev environment)."
  type        = list(string)
  default     = ["ref:refs/heads/main", "environment:dev"]
}

variable "terraform_subjects" {
  description = "OIDC 'sub' suffixes allowed to assume the terraform role."
  type        = list(string)
  default     = ["pull_request", "ref:refs/heads/main", "environment:infra-dev"]
}

variable "ecr_repository_arn" {
  type = string
}

variable "eks_cluster_arn" {
  type = string
}

variable "ssm_parameter_path" {
  description = "SSM path prefix the deploy role may read, e.g. /inventory-hub/dev/"
  type        = string
}

variable "tags" {
  type    = map(string)
  default = {}
}
