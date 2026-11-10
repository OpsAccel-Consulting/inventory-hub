# InventoryHub

A realistic sample service for learning cloud delivery end to end: a Flask web app and REST API backed by PostgreSQL, packaged as a container, running on **Amazon EKS**, provisioned with **Terraform**, and deployed by **GitHub Actions**.

```
                 ┌──────────── VPC 10.20.0.0/16 (ap-south-1) ────────────┐
 Users ──HTTP──▶ │  ALB (public subnets)                                 │
                 │    │                                                  │
                 │    ▼                                                  │
                 │  EKS pods: inventory-hub (private subnets) ──5432──▶  │ RDS PostgreSQL
                 │    │  Pod Identity                                    │ (database subnets)
                 │    ▼                                                  │
                 │  Secrets Manager (DB password, Flask key)             │
                 └───────────────────────────────────────────────────────┘
 GitHub Actions ──OIDC──▶ IAM role ──▶ ECR (images) + EKS (kubectl apply)
```

## What's inside

| Layer | Technology |
|---|---|
| App | Flask 3, SQLAlchemy 2, Flask-Migrate (Alembic), Jinja2 UI, JSON REST API |
| Database | RDS for PostgreSQL 17 (password managed by AWS in Secrets Manager) |
| Container | Multi-stage Docker image, non-root, gunicorn |
| Orchestration | Amazon EKS 1.35, managed node group (AL2023), Kustomize |
| Ingress | AWS Load Balancer Controller → Application Load Balancer |
| IAM for pods | EKS Pod Identity (no IRSA, no static keys) |
| IaC | Terraform ≥ 1.10, S3 backend with native locking, reusable modules |
| CI/CD | GitHub Actions with OIDC: lint → test → build → push → deploy → smoke test |

## Repository layout

```
.
├── .github/
│   ├── workflows/
│   │   ├── ci.yml              # PR checks: lint, tests on PostgreSQL, image build
│   │   ├── deploy.yml          # main: CI → build/push ECR → deploy EKS → smoke test
│   │   └── terraform.yml       # infra PRs: fmt/validate/plan; manual gated apply
│   ├── CODEOWNERS
│   ├── dependabot.yml
│   └── pull_request_template.md
├── src/inventory_hub/          # application package
│   ├── api/                    #   REST API blueprint (/api/v1)
│   ├── web/                    #   server-rendered UI blueprint
│   ├── health/                 #   /healthz, /readyz, /version
│   ├── models/                 #   SQLAlchemy models
│   ├── services/               #   business logic + validation
│   ├── templates/ static/      #   UI assets
│   ├── utils/                  #   logging, AWS secrets helper
│   ├── config.py               #   environment-based configuration
│   └── wsgi.py                 #   gunicorn entrypoint
├── migrations/                 # Alembic migrations
├── tests/
│   ├── unit/
│   └── integration/            # run against real PostgreSQL in CI
├── deploy/k8s/
│   ├── base/                   # Deployment, Service, Ingress, PDB, SA, Namespace
│   └── overlays/dev/           # env-specific config (app.env rendered by CI)
├── infra/terraform/
│   ├── bootstrap/              # one-time: state bucket
│   ├── modules/                # network, eks, rds-postgres, ecr, github-oidc,
│   │                           # pod-identity-role, aws-load-balancer-controller
│   └── environments/dev/       # composition for the dev environment
├── scripts/                    # bootstrap, deploy, smoke test, destroy helpers
├── docs/                       # architecture, runbook, ADRs
├── Dockerfile  docker-compose.yml  gunicorn.conf.py
├── Makefile  pyproject.toml  requirements*.txt
└── .pre-commit-config.yaml
```

## 1. Run it locally

```bash
python -m venv .venv && source .venv/bin/activate
make install          # deps + pre-commit hooks
make test             # 27 tests on SQLite
make run              # http://localhost:8000 with demo data

# or the full stack with PostgreSQL
make up               # docker compose: db + migrate/seed + web
```

## 2. Stand it up on AWS

**Prerequisites:** AWS CLI v2 (logged in as an admin), Terraform ≥ 1.10, kubectl, kustomize, Docker, GitHub CLI (`gh`), and a GitHub repository for this code.

> Cost: EKS control plane + 2 × t3.medium + NAT gateway + db.t4g.micro + ALB is roughly **US$ 7–8 per day** in ap-south-1. Run `make destroy` when you're done.

```bash
# 0. Point Terraform at YOUR GitHub repo
#    edit infra/terraform/environments/dev/terraform.tfvars → github_org / github_repo

# 1. State bucket (one time)
make tf-bootstrap

# 2. Infrastructure (~20 min: VPC, EKS, RDS, ECR, IAM, LB controller)
make tf-init
make tf-apply

# 3. Wire GitHub Actions to AWS (secrets + variables + environments)
./scripts/configure-github.sh <org>/<repo>

# 4. First deploy: push to main, or deploy from your machine
git push origin main          # triggers .github/workflows/deploy.yml
# or
make deploy
```

The deploy job prints the ALB URL in its summary. Open it to see the dashboard.

### GitHub configuration (set by `configure-github.sh`)

| Kind | Name | Value |
|---|---|---|
| Secret | `AWS_DEPLOY_ROLE_ARN` | `terraform output -raw github_deploy_role_arn` |
| Secret | `AWS_TERRAFORM_ROLE_ARN` | `terraform output -raw github_terraform_role_arn` |
| Variable | `AWS_REGION` | `ap-south-1` |
| Variable | `EKS_CLUSTER_NAME` | `inventory-hub-dev` |
| Variable | `ECR_REPOSITORY` | `inventory-hub` |
| Variable | `TF_STATE_BUCKET` | output of the bootstrap step |
| Environment | `dev` | app deployments |
| Environment | `infra-dev` | Terraform apply; add a required reviewer |

## 3. Ship a change

1. Branch, change code, `make test`, open a PR → **CI** runs lint, tests on PostgreSQL and an image build.
2. Merge → **Deploy** builds `inventory-hub:<git-sha>`, pushes to ECR, renders config from SSM, runs `kubectl apply -k`, waits for the rollout (automatic rollback on failure) and smoke-tests the live URL, including checking `/version` reports the new SHA.
3. Infra change → PR shows a Terraform plan; apply via **Actions → Terraform → Run workflow → apply** (approval required).

## API quick reference

```bash
URL=http://<alb-hostname>
curl $URL/api/v1/products?q=ssd
curl -X POST $URL/api/v1/products -H 'Content-Type: application/json' \
     -d '{"sku":"STG-HDD-8T","name":"8TB HDD","price":"15999","quantity":12}'
curl -X POST $URL/api/v1/products/1/stock -H 'Content-Type: application/json' -d '{"delta":-2}'
curl $URL/api/v1/summary
```

Full endpoint list: [`src/inventory_hub/api/routes.py`](src/inventory_hub/api/routes.py).

## Security notes

- No long-lived AWS keys anywhere: GitHub uses OIDC, pods use EKS Pod Identity.
- The DB password is generated and owned by RDS; the app reads it from Secrets Manager at startup.
- AWS account IDs never appear in committed files: Terraform outputs that contain ARNs are `sensitive`, environment values live in SSM, and a pre-commit hook blocks 12-digit numbers.
- Containers run as non-root with a read-only root filesystem; the namespace enforces the `restricted` Pod Security Standard.

## More

- [docs/architecture.md](docs/architecture.md): design and request flow
- [docs/runbook.md](docs/runbook.md): operating and troubleshooting
- [docs/adr/](docs/adr/): architecture decision records
