#!/usr/bin/env bash
# Render the Kubernetes ConfigMap env file for an environment from SSM
# Parameter Store (/inventory-hub/<env>/app/*) and print it to stdout.
#
#   ./scripts/render-app-env.sh dev <image-tag> > deploy/k8s/overlays/dev/app.env
set -euo pipefail

ENVIRONMENT="${1:?usage: render-app-env.sh <environment> <app-version>}"
APP_VERSION="${2:?usage: render-app-env.sh <environment> <app-version>}"
PROJECT="${PROJECT:-inventory-hub}"
SSM_PATH="/${PROJECT}/${ENVIRONMENT}/app/"

params=$(aws ssm get-parameters-by-path \
  --path "$SSM_PATH" \
  --query 'Parameters[].[Name,Value]' \
  --output text)

if [[ -z "$params" ]]; then
  echo "No parameters found under ${SSM_PATH} - has Terraform been applied?" >&2
  exit 1
fi

cat <<EOF
APP_ENV=production
ENV_NAME=${ENVIRONMENT}
LOG_LEVEL=INFO
LOG_JSON=true
APP_VERSION=${APP_VERSION}
EOF

while IFS=$'\t' read -r name value; do
  echo "${name##*/}=${value}"
done <<< "$params"
