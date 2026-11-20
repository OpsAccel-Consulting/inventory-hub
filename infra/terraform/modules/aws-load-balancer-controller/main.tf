# -----------------------------------------------------------------------------
# AWS Load Balancer Controller: turns Kubernetes Ingress objects into ALBs.
# IAM via EKS Pod Identity; installed with Helm.
#
# iam_policy.json is the upstream policy from
# kubernetes-sigs/aws-load-balancer-controller/docs/install/iam_policy.json -
# refresh it when bumping chart_version.
# -----------------------------------------------------------------------------

locals {
  namespace       = "kube-system"
  service_account = "aws-load-balancer-controller"
}

module "identity" {
  source = "../pod-identity-role"

  role_name       = "${var.cluster_name}-aws-lb-controller"
  cluster_name    = var.cluster_name
  namespace       = local.namespace
  service_account = local.service_account
  # Minified to stay under the 10 KB inline-policy limit
  policy_json = jsonencode(jsondecode(file("${path.module}/iam_policy.json")))
  tags        = var.tags
}

resource "helm_release" "this" {
  name       = "aws-load-balancer-controller"
  repository = "https://aws.github.io/eks-charts"
  chart      = "aws-load-balancer-controller"
  version    = var.chart_version
  namespace  = local.namespace

  wait    = true
  timeout = 600

  values = [yamlencode({
    clusterName  = var.cluster_name
    region       = var.region
    vpcId        = var.vpc_id
    replicaCount = 2
    serviceAccount = {
      create = true
      name   = local.service_account
    }
    resources = {
      requests = { cpu = "50m", memory = "128Mi" }
      limits   = { memory = "256Mi" }
    }
  })]

  # The Pod Identity association must exist before the controller pods start,
  # otherwise they come up without AWS credentials.
  depends_on = [module.identity]
}
