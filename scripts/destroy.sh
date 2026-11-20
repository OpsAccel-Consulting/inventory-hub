#!/usr/bin/env bash
# Tear down the dev environment in the right order.
#
# The ALB is created by the AWS Load Balancer Controller (not Terraform), so the
# Kubernetes resources must be deleted first - otherwise the ALB and its
# security groups block VPC deletion and `terraform destroy` hangs.
#
#   ./scripts/destroy.sh
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TF_DIR="${ROOT}/infra/terraform/environments/dev"

CLUSTER=$(terraform -chdir="$TF_DIR" output -raw cluster_name)
REGION=$(terraform -chdir="$TF_DIR" output -raw region)

read -r -p "Destroy EVERYTHING in '${CLUSTER}' (${REGION})? Type the cluster name: " answer
[[ "$answer" == "$CLUSTER" ]] || { echo "Aborted."; exit 1; }

aws eks update-kubeconfig --name "$CLUSTER" --region "$REGION" > /dev/null

echo "Deleting application namespace (removes the ALB)..."
kubectl delete namespace inventory-hub --ignore-not-found --wait=true --timeout=5m

echo "Waiting for load balancers tagged for this cluster to disappear..."
for _ in $(seq 1 30); do
  remaining=$(aws elbv2 describe-load-balancers --region "$REGION" \
    --query "LoadBalancers[?starts_with(LoadBalancerName, 'inventory-hub-')].LoadBalancerName" \
    --output text)
  [[ -z "$remaining" ]] && break
  sleep 10
done

terraform -chdir="$TF_DIR" destroy -input=false
