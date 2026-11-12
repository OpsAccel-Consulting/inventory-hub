# CLAUDE.md — inventory-hub

Flask 3 + PostgreSQL inventory service. Ships as a container to Amazon EKS (dev, ap-south-1).
Terraform provisions the infrastructure and GitHub Actions (OIDC) does every deploy.
Merging to `main` deploys to dev automatically.

## Layout
- `src/inventory_hub/`: app package. The `api/` (/api/v1), `web/` (UI) and `health/` blueprints are thin;
  logic lives in `services/` and models in `models/`.
- `migrations/`: Alembic via Flask-Migrate. `env.py` takes a Postgres advisory lock.
- `tests/unit/`: SQLite in memory. `tests/integration/`: needs Postgres through `TEST_DATABASE_URL`.
- `deploy/k8s/base/` plus `overlays/dev/`: Kustomize. `overlays/dev/app.env` holds only placeholders.
- `infra/terraform/`: `bootstrap/` (state bucket, local state), `modules/*`, and `environments/dev/` (composition only).
- `scripts/`: bootstrap, manual deploy, destroy, SSM render, smoke test, GitHub config.
- `.github/workflows/`: `ci.yml` (PR), `deploy.yml` (push to main), `terraform.yml` (infra PR plus a manual, gated apply).
- `docs/`: architecture, runbook, ADRs. Read `docs/adr/` before changing a design decision.

## Guardrails
- NEVER run `terraform apply`, `terraform destroy` or `terraform import`, or any state-mutating terraform command.
- NEVER run `make tf-bootstrap`, `make tf-apply`, `make deploy` or `make destroy`.
- NEVER run `scripts/deploy-manual.sh`, `destroy.sh`, `bootstrap-state.sh` or `configure-github.sh`
  (the last one writes GitHub secrets and variables).
- NEVER run `kubectl apply`, `delete`, `edit`, `patch`, `scale`, `rollout undo` or `rollout restart`.
- NEVER run AWS CLI commands that create, modify or delete resources. Changes go through the pipelines.
- ASK before anything that needs AWS credentials or remote state, even when it's read-only:
  `make tf-init`, `make tf-plan`, `make kubeconfig`, `terraform output`, `scripts/render-app-env.sh`
  (it prints ARNs that contain the account ID).
- NEVER read `*.tfstate*`, `.env`/`.env.*` (`.env.example` is fine) or any `*.tfvars` that holds secrets.
- NEVER hard-code AWS account IDs, ARNs with account IDs, usernames, passwords, access keys or
  hostnames in committed files. Config comes from SSM and secrets from Secrets Manager.
- NEVER commit a rendered `deploy/k8s/overlays/dev/app.env`. It must keep `REPLACED_BY_PIPELINE`.
- ALWAYS mark Terraform outputs that contain ARNs or the ECR URL as `sensitive = true`.
- NEVER bypass the pre-commit hooks (`--no-verify`).

## Conventions
- Python 3.12, ruff with line length 100 (rules in `pyproject.toml`). `migrations/` is excluded from ruff.
- ALWAYS start modules with `from __future__ import annotations`.
- ALWAYS keep routes thin. DB work goes in `services/inventory_service.py` and input checks in
  `services/validation.py`, which both the API and the UI use.
- Errors: raise `ValidationError` (422), `NotFoundError` (404) or `ConflictError` (409). `errors.py`
  maps them to JSON under `/api/` and HTML everywhere else. Don't return ad-hoc error responses.
- Money is `Numeric(10,2)`/`Decimal`, serialized as a string. Timestamps are timezone-aware UTC.
- Prefer DB `CheckConstraint`s for invariants, mirrored in validation.
- Config comes from environment variables in `config.py`. Add new settings there with a safe default,
  and if they are needed on AWS, also add them to the `aws_ssm_parameter.app_config` map in
  `environments/dev/main.tf`.
- Terraform: resources go in `modules/<name>/` (`main.tf`, `variables.tf`, `outputs.tf`, `versions.tf`).
  `environments/dev/main.tf` only composes them. Providers use `~> 6.0` in env and bootstrap, `>= 6.0` in modules.
- K8s: shared manifests go in `base/` and environment differences go in overlay patches.
  Containers run as non-root (UID 10001) with a read-only root filesystem, because the namespace enforces `restricted`.
- Image tags are the first 12 characters of the git SHA. `newTag: latest` in base is a placeholder.

## Verification
Run these before saying a change is done. They mirror the CI jobs.
- Python: `make lint`, then `make test`. `make fmt` auto-fixes Python and Terraform.
- Postgres behaviour (integration tests and migrations): bring up Postgres with `make up` or docker, then
  `TEST_DATABASE_URL=postgresql+psycopg2://app:app@localhost:5432/<db> pytest -m integration`
  and `flask db upgrade && flask db downgrade base && flask db upgrade`.
- New migration: `make migration m="..."`. ALWAYS review the generated file and make sure the
  downgrade works.
- Terraform (no credentials needed): `terraform fmt -check -recursive infra/terraform` and
  `terraform -chdir=infra/terraform/environments/dev init -backend=false && terraform -chdir=infra/terraform/environments/dev validate`.
- K8s: `kubectl kustomize deploy/k8s/overlays/dev` must render.
- Everything: `pre-commit run --all-files`.
- If a tool is missing locally, say which check you couldn't run. Don't skip it silently.

## Workflow
- ALWAYS plan first: list the files you'll touch and how you'll verify, then wait for my OK.
- One logical change per PR. Don't make drive-by fixes; list them as follow-ups.
- ALWAYS work on a branch (`feat/`, `fix/`, `chore/`). NEVER commit or push to `main`.
- Fill in `.github/pull_request_template.md`. Infra PRs: the Terraform plan in the PR is the review artifact.
- When I correct you on something specific to this repo, propose a one-line addition to this file and show
  it to me. Don't edit CLAUDE.md without my approval.

## Known issues / traps
- `terraform fmt -check` fails today on `infra/terraform/modules/github-oidc/main.tf:18` (`provider_arn =var...`),
  so the validate job in `terraform.yml` fails on every infra PR until that's fixed.
- Local machine is Windows. `make`, `ruff`, `pytest`, `kubectl`, `kustomize`, `docker` and `pre-commit` aren't on PATH
  (only `terraform` and `python` are). The Makefile assumes `/bin/bash`. Run the underlying commands in
  Git Bash from a venv, with `PYTHONPATH=src` and `FLASK_APP=inventory_hub.wsgi`.
- A green `make test` only proves SQLite. The integration tests skip silently unless `TEST_DATABASE_URL` is Postgres,
  and CHECK constraints and `ilike` behave differently on Postgres.
- Migrations run in the `migrate` initContainer on every rollout, and an automatic rollback does NOT undo them.
  Migrations must be expand/contract and backward-compatible with the previous release.
- `.terraform.lock.hcl` isn't committed (`.gitignore` says it should be). `init` creates one, so don't commit it
  inside an unrelated PR.
- `backend.hcl` has `bucket = "REPLACE_WITH_STATE_BUCKET"`. `make tf-init` fails until bootstrap runs,
  and CI overrides the bucket with `-backend-config`.
- The pre-commit hook rejects any standalone 12-digit number (account-ID guard), test data included.
- Names that must stay in sync: namespace and ServiceAccount `inventory-hub` (Terraform `locals` and `deploy/k8s/base`),
  deployment `inventory-hub` and label `app.kubernetes.io/component=web` (`deploy.yml` rollback/logs, PDB, Service),
  ALB name prefix `inventory-hub-` (`destroy.sh`).
- `/healthz`, `/readyz` and `/version` are a contract: probes, the ALB health check, CI's container test and `smoke-test.sh`
  (which `sed`-parses `"version":` from `/version`) all depend on them.
- Path filters: `ci.yml` ignores `infra/terraform/**` and `*.md`. `deploy.yml` doesn't trigger on `scripts/` or
  `Makefile` changes, even though it runs `scripts/*`.
- Stale or placeholder text: `serviceaccount.yaml` refers to `modules/eks-app-identity` (the module is actually `pod-identity-role`),
  and the `Dockerfile` OCI source label is `github.com/your-org/...`.
- Known TODOs, which should be their own PRs: Ingress is HTTP-only, the pipeline roles get `AmazonEKSClusterAdminPolicy`,
  the Terraform role has `AdministratorAccess`, and `eks_public_access_cidrs` defaults to `0.0.0.0/0`.
