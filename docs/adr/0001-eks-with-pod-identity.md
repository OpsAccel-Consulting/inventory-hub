# ADR 0001: Run on EKS and use EKS Pod Identity for AWS access

- **Status:** Accepted
- **Date:** 2026-10-13

## Context

The service needs a container platform and a way for pods to call AWS APIs (Secrets Manager) without static credentials. Options considered: ECS Fargate, EKS with IRSA, and EKS with Pod Identity.

## Decision

Use **Amazon EKS** with a managed node group, and **EKS Pod Identity** for pod IAM.

## Consequences

- Kubernetes skills and manifests transfer to other clouds; there's a rich ecosystem (Load Balancer Controller, Karpenter, Argo CD).
- Higher baseline cost and more moving parts than ECS Fargate (control plane fee, node management, add-on upgrades).
- Pod Identity needs no per-cluster OIDC provider and no ServiceAccount annotations. Trust policies are identical across clusters, so the same role works after a cluster rebuild.
- Requires the `eks-pod-identity-agent` add-on, which is managed in Terraform.
