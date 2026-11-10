# -----------------------------------------------------------------------------
# GitHub Actions -> AWS federation (no long-lived access keys).
#
# Two roles with different blast radius:
#   deploy role    - push images to ECR, read app config from SSM, talk to EKS.
#                    Trusted only for the main branch and the GitHub "dev"
#                    environment on this repo.
#   terraform role - plan on pull requests, apply from the "infra-dev"
#                    environment (which should require a reviewer).
# -----------------------------------------------------------------------------

data "aws_partition" "current" {}

locals {
  partition    = data.aws_partition.current.partition
  repo         = "${var.github_org}/${var.github_repo}"
  oidc_host    = "token.actions.githubusercontent.com"
  provider_arn =var.create_oidc_provider ? aws_iam_openid_connect_provider.github[0].arn : data.aws_iam_openid_connect_provider.github[0].arn
}

resource "aws_iam_openid_connect_provider" "github" {
  count          = var.create_oidc_provider ? 1 : 0
  url            = "https://${local.oidc_host}"
  client_id_list = ["sts.amazonaws.com"]
  tags           = var.tags
}

# An account can only have one provider per URL - reuse it if it already exists.
data "aws_iam_openid_connect_provider" "github" {
  count = var.create_oidc_provider ? 0 : 1
  url   = "https://${local.oidc_host}"
}

data "aws_iam_policy_document" "trust" {
  for_each = {
    deploy    = var.deploy_subjects
    terraform = var.terraform_subjects
  }

  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [local.provider_arn]
    }

    condition {
      test     = "StringEquals"
      variable = "${local.oidc_host}:aud"
      values   = ["sts.amazonaws.com"]
    }

    condition {
      test     = "StringLike"
      variable = "${local.oidc_host}:sub"
      values   = [for s in each.value : "repo:${local.repo}:${s}"]
    }
  }
}

# ---------- Deploy role (application CI/CD) ----------

resource "aws_iam_role" "deploy" {
  name                 = "${var.name_prefix}-gha-deploy"
  assume_role_policy   = data.aws_iam_policy_document.trust["deploy"].json
  max_session_duration = 3600
  tags                 = var.tags
}

data "aws_iam_policy_document" "deploy" {
  statement {
    sid       = "EcrAuth"
    actions   = ["ecr:GetAuthorizationToken"]
    resources = ["*"]
  }

  statement {
    sid = "EcrPushPull"
    actions = [
      "ecr:BatchCheckLayerAvailability",
      "ecr:BatchGetImage",
      "ecr:CompleteLayerUpload",
      "ecr:DescribeImages",
      "ecr:DescribeImageScanFindings",
      "ecr:GetDownloadUrlForLayer",
      "ecr:InitiateLayerUpload",
      "ecr:PutImage",
      "ecr:UploadLayerPart",
    ]
    resources = [var.ecr_repository_arn]
  }

  statement {
    sid       = "EksDescribe"
    actions   = ["eks:DescribeCluster"]
    resources = [var.eks_cluster_arn]
  }

  statement {
    sid       = "ReadAppConfig"
    actions   = ["ssm:GetParametersByPath", "ssm:GetParameters", "ssm:GetParameter"]
    resources = ["arn:${local.partition}:ssm:*:*:parameter${var.ssm_parameter_path}*"]
  }
}

resource "aws_iam_role_policy" "deploy" {
  name   = "deploy"
  role   = aws_iam_role.deploy.id
  policy = data.aws_iam_policy_document.deploy.json
}

# ---------- Terraform role (infrastructure CI/CD) ----------

resource "aws_iam_role" "terraform" {
  name                 = "${var.name_prefix}-gha-terraform"
  assume_role_policy   = data.aws_iam_policy_document.trust["terraform"].json
  max_session_duration = 3600
  tags                 = var.tags
}

# TODO: AdministratorAccess is broader than needed. Replace with a
# least-privilege policy (or a permissions boundary).
resource "aws_iam_role_policy_attachment" "terraform" {
  role       = aws_iam_role.terraform.name
  policy_arn = "arn:${local.partition}:iam::aws:policy/AdministratorAccess"
}
