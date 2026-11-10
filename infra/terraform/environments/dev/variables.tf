# ---------- General ----------

variable "project" {
  type    = string
  default = "inventory-hub"
}

variable "environment" {
  type    = string
  default = "dev"
}

variable "region" {
  type    = string
  default = "ap-south-1"
}

variable "cost_center" {
  type    = string
  default = "engineering"
}

# ---------- GitHub ----------

variable "github_org" {
  description = "GitHub org/user owning the repository (used in the OIDC trust policy)."
  type        = string
}

variable "github_repo" {
  description = "GitHub repository name."
  type        = string
  default     = "inventory-hub"
}

variable "create_github_oidc_provider" {
  description = "false if this AWS account already has the token.actions.githubusercontent.com provider."
  type        = bool
  default     = true
}

# ---------- Network ----------

variable "vpc_cidr" {
  type    = string
  default = "10.20.0.0/16"
}

variable "az_count" {
  type    = number
  default = 2
}

variable "single_nat_gateway" {
  type    = bool
  default = true
}

# ---------- EKS ----------

variable "kubernetes_version" {
  type    = string
  default = "1.35"
}

variable "eks_public_access_cidrs" {
  description = "Who may reach the EKS API endpoint. Narrow to your IP (x.x.x.x/32) for real use."
  type        = list(string)
  default     = ["0.0.0.0/0"]
}

variable "cluster_admin_arns" {
  description = "Additional IAM principals (e.g. your SSO admin role) to grant cluster-admin."
  type        = list(string)
  default     = []
}

variable "node_instance_types" {
  type    = list(string)
  default = ["t3.medium"]
}

variable "node_capacity_type" {
  type    = string
  default = "ON_DEMAND"
}

variable "node_min_size" {
  type    = number
  default = 2
}

variable "node_desired_size" {
  type    = number
  default = 2
}

variable "node_max_size" {
  type    = number
  default = 4
}

# ---------- Database ----------

variable "db_engine_version" {
  type    = string
  default = "17"
}

variable "db_instance_class" {
  type    = string
  default = "db.t4g.micro"
}

variable "db_multi_az" {
  type    = bool
  default = false
}

variable "db_deletion_protection" {
  type    = bool
  default = false
}

variable "db_skip_final_snapshot" {
  type    = bool
  default = true
}

# ---------- Misc ----------

variable "ecr_force_delete" {
  type    = bool
  default = true
}

variable "secret_recovery_window_days" {
  description = "0 = delete immediately on destroy (handy for labs that are rebuilt often)."
  type        = number
  default     = 0
}
