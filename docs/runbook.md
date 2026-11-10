# Runbook: inventory-hub (dev)

```bash
make kubeconfig                    # point kubectl at the cluster
kubectl -n inventory-hub get pods,svc,ingress
```

## Common checks

| Question | Command |
|---|---|
| Which version is live? | `curl http://<alb>/version` |
| Rollout progress | `kubectl -n inventory-hub rollout status deploy/inventory-hub` |
| App logs | `kubectl -n inventory-hub logs -l app.kubernetes.io/component=web --tail=100` |
| Migration logs | `kubectl -n inventory-hub logs <pod> -c migrate` |
| Recent events | `kubectl -n inventory-hub get events --sort-by=.lastTimestamp` |
| LB controller logs | `kubectl -n kube-system logs deploy/aws-load-balancer-controller` |
| Pod Identity mapping | `aws eks list-pod-identity-associations --cluster-name inventory-hub-dev` |

## Symptoms

**Pods stuck in `Init:CrashLoopBackOff`.** The migration failed. Check `logs -c migrate`. Usually the DB is unreachable (security group) or a migration is broken.

**Pods Running but `0/1 READY`.** `/readyz` is failing, so the DB is unreachable. Check the RDS status and that the pod can resolve `DB_HOST`. Credentials errors show as `AccessDeniedException` from Secrets Manager: verify the Pod Identity association and that the `eks-pod-identity-agent` add-on is healthy.

**Ingress has no ADDRESS.** Run `kubectl describe ingress`, then check the LB controller logs. Typical causes are missing subnet tags or controller IAM.

**ALB returns 502/503.** No healthy targets. Check the target group health in the console and pod readiness.

**Deploy job fails at "Configure kubectl" with `Unauthorized`.** The deploy role has no EKS access entry. Re-run `terraform apply`.

## Rollback

The pipeline rolls back automatically when a rollout fails. Manually:

```bash
kubectl -n inventory-hub rollout history deploy/inventory-hub
kubectl -n inventory-hub rollout undo deploy/inventory-hub [--to-revision=N]
```

Or re-run the **Deploy** workflow for an older commit. Images are immutable and tagged by SHA.

Database migrations are **not** rolled back automatically. Write migrations that are backward compatible with the previous release (expand, then contract).

## Teardown

```bash
make destroy    # deletes the namespace (and ALB) first, then terraform destroy
```

The state bucket in `bootstrap/` has `prevent_destroy` and is kept on purpose.
