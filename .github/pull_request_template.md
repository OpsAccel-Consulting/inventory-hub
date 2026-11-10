## What & why

<!-- One or two sentences on the change and the reason for it. -->

## Type
- [ ] Application (src/, migrations/)
- [ ] Infrastructure (infra/terraform/)
- [ ] Kubernetes manifests (deploy/k8s/)
- [ ] CI/CD (.github/workflows/)

## Checklist
- [ ] Tests added/updated and `make test` passes
- [ ] DB migration included (if models changed) and is backward compatible
- [ ] Terraform plan reviewed (infra changes)
- [ ] No secrets, AWS account IDs or ARNs committed
- [ ] Docs / runbook updated if behaviour changed
