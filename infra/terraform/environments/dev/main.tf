# -----------------------------------------------------------------------------
# inventory-hub :: dev environment
#
#   Internet -> ALB (public subnets) -> EKS pods (private subnets) -> RDS (db subnets)
#
# Composition only - all resources live in ../../modules.
# -----------------------------------------------------------------------------

data "aws_availability_zones" "available" {
  state = "available"
}

locals {
  name         = "${var.project}-${var.environment}"
  cluster_name = local.name
  ssm_app_path = "/${var.project}/${var.environment}/app/"
  azs          = slice(data.aws_availability_zones.available.names, 0, var.az_count)

  # Must match deploy/k8s/base (namespace + ServiceAccount)
  k8s_namespace       = "inventory-hub"
  k8s_service_account = "inventory-hub"

  tags = {
    Project     = var.project
    Environment = var.environment
    ManagedBy   = "terraform"
    Repository  = "${var.github_org}/${var.github_repo}"
    CostCenter  = var.cost_center
  }
}

# ---------- Network ----------

module "network" {
  source = "../../modules/network"

  name               = local.name
  cidr               = var.vpc_cidr
  azs                = local.azs
  cluster_name       = local.cluster_name
  single_nat_gateway = var.single_nat_gateway
}

# ---------- Container registry ----------

module "ecr" {
  source = "../../modules/ecr"

  name         = var.project
  force_delete = var.ecr_force_delete
}

# ---------- Kubernetes ----------

module "eks" {
  source = "../../modules/eks"

  cluster_name         = local.cluster_name
  kubernetes_version   = var.kubernetes_version
  subnet_ids           = module.network.private_subnet_ids
  public_access_cidrs  = var.eks_public_access_cidrs
  node_instance_types  = var.node_instance_types
  node_capacity_type   = var.node_capacity_type
  node_min_size        = var.node_min_size
  node_desired_size    = var.node_desired_size
  node_max_size        = var.node_max_size
  admin_principal_arns = var.cluster_admin_arns
}

module "aws_load_balancer_controller" {
  source = "../../modules/aws-load-balancer-controller"

  cluster_name = module.eks.cluster_name
  region       = var.region
  vpc_id       = module.network.vpc_id

  # Nodes must exist for the controller pods to schedule
  depends_on = [module.eks]
}

# ---------- Database ----------

module "rds" {
  source = "../../modules/rds-postgres"

  identifier                 = local.name
  vpc_id                     = module.network.vpc_id
  subnet_ids                 = module.network.database_subnet_ids
  allowed_security_group_ids = [module.eks.cluster_security_group_id]
  engine_version             = var.db_engine_version
  instance_class             = var.db_instance_class
  multi_az                   = var.db_multi_az
  deletion_protection        = var.db_deletion_protection
  skip_final_snapshot        = var.db_skip_final_snapshot
  apply_immediately          = true
}

# ---------- Application secrets & identity ----------

resource "random_password" "flask_secret_key" {
  length  = 64
  special = false
}

resource "aws_secretsmanager_secret" "app" {
  name                    = "${var.project}/${var.environment}/app"
  description             = "Application secrets for ${local.name}"
  recovery_window_in_days = var.secret_recovery_window_days
}

resource "aws_secretsmanager_secret_version" "app" {
  secret_id     = aws_secretsmanager_secret.app.id
  secret_string = jsonencode({ secret_key = random_password.flask_secret_key.result })
}

module "app_identity" {
  source = "../../modules/pod-identity-role"

  role_name       = "${local.name}-app"
  cluster_name    = module.eks.cluster_name
  namespace       = local.k8s_namespace
  service_account = local.k8s_service_account

  policy_json = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid    = "ReadAppSecrets"
      Effect = "Allow"
      Action = ["secretsmanager:GetSecretValue", "secretsmanager:DescribeSecret"]
      Resource = [
        module.rds.master_user_secret_arn,
        aws_secretsmanager_secret.app.arn,
      ]
    }]
  })
}

# Non-secret runtime config, read by the deploy pipeline and rendered into the
# Kubernetes ConfigMap. Keeps environment-specific values out of git.
resource "aws_ssm_parameter" "app_config" {
  for_each = {
    AWS_REGION     = var.region
    DB_HOST        = module.rds.address
    DB_PORT        = tostring(module.rds.port)
    DB_NAME        = module.rds.database_name
    DB_SECRET_ARN  = module.rds.master_user_secret_arn
    APP_SECRET_ARN = aws_secretsmanager_secret.app.arn
  }

  name  = "${local.ssm_app_path}${each.key}"
  type  = "String"
  value = each.value
}

# ---------- CI/CD identity (GitHub Actions OIDC) ----------

module "github_oidc" {
  source = "../../modules/github-oidc"

  name_prefix          = local.name
  github_org           = var.github_org
  github_repo          = var.github_repo
  create_oidc_provider = var.create_github_oidc_provider
  ecr_repository_arn   = module.ecr.repository_arn
  eks_cluster_arn      = module.eks.cluster_arn
  ssm_parameter_path   = "/${var.project}/${var.environment}/"
}

# Let the pipelines talk to the Kubernetes API.
# (Defined here rather than in the eks module to avoid a module dependency cycle.)
locals {
  pipeline_roles = {
    deploy    = module.github_oidc.deploy_role_arn
    terraform = module.github_oidc.terraform_role_arn
  }
}

resource "aws_eks_access_entry" "pipelines" {
  for_each      = toset(["deploy", "terraform"])
  cluster_name  = module.eks.cluster_name
  principal_arn = local.pipeline_roles[each.key]
}

resource "aws_eks_access_policy_association" "pipelines" {
  for_each      = aws_eks_access_entry.pipelines
  cluster_name  = module.eks.cluster_name
  principal_arn = each.value.principal_arn
  # TODO: cluster-admin is broader than needed; scope the deploy role to the
  # app namespace (AmazonEKSEditPolicy + namespace access scope).
  policy_arn = "arn:aws:eks::aws:cluster-access-policy/AmazonEKSClusterAdminPolicy"

  access_scope {
    type = "cluster"
  }
}
