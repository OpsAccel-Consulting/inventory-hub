# ADR 0002: Environment config comes from SSM, not git

- **Status:** Accepted
- **Date:** 2026-10-13

## Context

The app needs the database host and the ARNs of its secrets. These values are created by Terraform, differ per environment, and contain the AWS account ID, which company policy says must not be committed to source control.

## Decision

Terraform writes non-secret runtime config to **SSM Parameter Store** under `/<project>/<env>/app/`. The deploy pipeline renders it into the Kustomize `app.env` just before `kubectl apply`. Secrets themselves stay in **Secrets Manager** and are fetched by the app with its Pod Identity role.

## Consequences

- Git holds only placeholders; no account IDs, hostnames or secrets.
- Terraform is the single source of truth: change infra, and the next deploy picks up new values.
- A deploy needs AWS access to SSM (granted to the deploy role).
- Config changes ship only through a deploy, which is a deliberate audit point.
