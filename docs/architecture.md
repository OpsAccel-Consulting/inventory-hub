# Architecture

## Components

| Component | Where | Notes |
|---|---|---|
| Application Load Balancer | public subnets | Created by the AWS Load Balancer Controller from the `Ingress`. Targets pod IPs directly (`target-type: ip`). |
| inventory-hub pods | private subnets, EKS managed node group | 2 replicas spread across AZs, gunicorn with threads. |
| RDS PostgreSQL 17 | database subnets (no internet route) | Accepts 5432 only from the EKS cluster security group. TLS enforced. |
| Secrets Manager | regional | `rds!db-…` (RDS-managed master credentials) and `inventory-hub/dev/app` (Flask secret key). |
| SSM Parameter Store | `/inventory-hub/dev/app/*` | Non-secret runtime config (DB host, secret ARNs). |
| ECR | `inventory-hub` | Immutable tags (git SHA), scan on push, lifecycle policy. |
| NAT gateway | one, in the first public subnet | Egress for nodes (image pulls, AWS APIs). |

## Request flow

1. Browser → ALB (HTTP :80) → pod IP :8000.
2. The ALB health-checks `/readyz`, which runs `SELECT 1` against the database. A pod that loses its DB connection stops receiving traffic but is **not** restarted.
3. Kubernetes liveness uses `/healthz`, which never touches dependencies, so a database outage cannot cause a restart storm.

## Pod startup

1. The **initContainer** runs `flask db upgrade`. `migrations/env.py` takes a PostgreSQL advisory lock, so parallel pods migrate one at a time.
2. The app container starts. `config.py` sees `DB_SECRET_ARN`, and boto3 fetches the credentials using the **Pod Identity** role (`inventory-hub-dev-app`), which can read only those two secrets.

## Configuration flow

```
Terraform ──writes──▶ SSM /inventory-hub/dev/app/*
                           │
deploy.yml ──reads──▶ scripts/render-app-env.sh ──▶ overlays/dev/app.env
                           │
kustomize configMapGenerator ──▶ ConfigMap inventory-hub-config-<hash>
                           │
Deployment envFrom ──▶ pod environment
```

The ConfigMap name includes a content hash, so a config change automatically rolls the Deployment.

## CI/CD identity

| Role | Trusted `sub` claims | Can do |
|---|---|---|
| `inventory-hub-dev-gha-deploy` | `ref:refs/heads/main`, `environment:dev` | push to the ECR repo, read SSM `/inventory-hub/dev/*`, describe the cluster; EKS access entry |
| `inventory-hub-dev-gha-terraform` | `pull_request`, `ref:refs/heads/main`, `environment:infra-dev` | AdministratorAccess (to be tightened); EKS access entry |

## Network

| Tier | CIDRs | Route |
|---|---|---|
| public | 10.20.0.0/24, 10.20.1.0/24 | IGW |
| private | 10.20.16.0/20, 10.20.32.0/20 | NAT |
| database | 10.20.200.0/24, 10.20.201.0/24 | local only |

Private subnets are /20 because the VPC CNI gives every pod a VPC IP address.
