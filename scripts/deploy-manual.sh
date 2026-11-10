#!/usr/bin/env bash
# Build, push and deploy from your workstation - same steps as deploy.yml.
# Useful for the very first deployment or when debugging the pipeline.
#
#   ./scripts/deploy-manual.sh [image-tag]
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TF_DIR="${ROOT}/infra/terraform/environments/dev"
OVERLAY="${ROOT}/deploy/k8s/overlays/dev"
TAG="${1:-manual-$(git -C "$ROOT" rev-parse --short=12 HEAD)}"

REGION=$(terraform -chdir="$TF_DIR" output -raw region)
CLUSTER=$(terraform -chdir="$TF_DIR" output -raw cluster_name)
REPO=$(terraform -chdir="$TF_DIR" output -raw ecr_repository_name)
REPO_URL=$(terraform -chdir="$TF_DIR" output -raw ecr_repository_url)
REGISTRY="${REPO_URL%%/*}"

aws ecr get-login-password --region "$REGION" | docker login --username AWS --password-stdin "$REGISTRY" > /dev/null
# --quiet keeps the registry URL (which contains the account ID) off screen
docker build --quiet --platform linux/amd64 --build-arg "APP_VERSION=${TAG}" -t "${REPO_URL}:${TAG}" "$ROOT"
docker push "${REPO_URL}:${TAG}" > /dev/null
echo "Pushed ${REPO}:${TAG}"

aws eks update-kubeconfig --name "$CLUSTER" --region "$REGION" > /dev/null

# Render into a temp copy so the committed overlay keeps its placeholders
WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT
cp -r "${ROOT}/deploy/k8s" "$WORK/"
"${ROOT}/scripts/render-app-env.sh" dev "$TAG" > "$WORK/k8s/overlays/dev/app.env"
(cd "$WORK/k8s/overlays/dev" && kustomize edit set image "inventory-hub=${REPO_URL}:${TAG}")

kubectl apply -k "$WORK/k8s/overlays/dev"
kubectl -n inventory-hub rollout status deployment/inventory-hub --timeout=6m

HOST=$("${ROOT}/scripts/wait-for-ingress.sh" inventory-hub inventory-hub)
"${ROOT}/scripts/smoke-test.sh" "http://${HOST}" "$TAG"
echo "App: http://${HOST}"
