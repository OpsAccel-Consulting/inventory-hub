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
| LB controller leader | `kubectl -n kube-system get lease aws-load-balancer-controller-leader -o jsonpath='{.spec.holderIdentity}'` |
| Pod Identity mapping | `aws eks list-pod-identity-associations --cluster-name inventory-hub-dev` |

## Symptoms

**Pods stuck in `Init:CrashLoopBackOff`.** The migration failed. Check `logs -c migrate`. Usually the DB is unreachable (security group) or a migration is broken.

**Pods Running but `0/1 READY`.** `/readyz` is failing, so the DB is unreachable. Check the RDS status and that the pod can resolve `DB_HOST`. Credentials errors show as `AccessDeniedException` from Secrets Manager: verify the Pod Identity association and that the `eks-pod-identity-agent` add-on is healthy.

**Pods Running, but `kubectl get pods -o wide` shows `READINESS GATES 0/1`.** The pod is healthy but the ALB doesn't see it as healthy yet. Normal for up to a minute after a pod starts (two 15-second health checks). If it stays at `0/1`, check the target group health in the console and the LB controller logs. On a first deploy it waits until the ALB itself exists.

**Ingress has no ADDRESS.** Run `kubectl describe ingress`, then check the LB controller logs. Typical causes are missing subnet tags or controller IAM.

**ALB returns 502/503.** No healthy targets. Check the target group health in the console and pod readiness.

**Deploy job fails at "Configure kubectl" with `Unauthorized`.** The deploy role has no EKS access entry. Re-run `terraform apply`.

**`make env-up` / `env-down` stops with `AccessDenied ... not authorized to perform: <action>`** (running as `inventory-deployer`). The deployer policy is missing that action. Add it to `infra/iam/deployer-*-policy.json`, publish a new policy version and re-run. See [deployer-access.md](deployer-access.md#6-when-something-is-denied).

**kubectl returns `Unauthorized` on your machine.** Your profile isn't the identity that created the cluster and has no access entry. Use the profile that ran `env-up`, or add your ARN to `cluster_admin_arns`.

## Draining a node (instance-type change, AMI or Kubernetes upgrade)

Only one AWS Load Balancer Controller replica is active at a time: the one holding the leader lease. If you drain the node that runs it, the other replica takes over after the lease expires (about 15 seconds) and a reconcile. Until then nobody deregisters the app pods being evicted from that node, so the ALB can keep sending requests to them. The app's 30-second `preStop` covers this window, but moving the leader first removes the risk.

This is a manual step. Do it yourself before draining; don't automate it.

```bash
# 1. Which controller pod is the leader, and which node is it on?
LEADER=$(kubectl -n kube-system get lease aws-load-balancer-controller-leader \
  -o jsonpath='{.spec.holderIdentity}')
LEADER_POD=${LEADER%%_*}                       # holderIdentity is <pod-name>_<uuid>
kubectl -n kube-system get pod "$LEADER_POD" -o wide

# 2. Only if it runs on the node you are about to drain: delete it and wait for the
#    lease to move to the other replica
kubectl -n kube-system delete pod "$LEADER_POD"
until [[ "$(kubectl -n kube-system get lease aws-load-balancer-controller-leader \
  -o jsonpath='{.spec.holderIdentity}')" != "$LEADER" ]]; do sleep 2; done
kubectl -n kube-system get lease aws-load-balancer-controller-leader \
  -o jsonpath='{.spec.holderIdentity}{"\n"}'

# 3. Drain the node (the PodDisruptionBudget keeps at least one app pod running)
kubectl drain <node-name> --ignore-daemonsets --delete-emptydir-data

# 4. Check the app while it drains (from a second terminal)
while true; do curl -s -o /dev/null -w '%{http_code} ' http://<alb>/healthz; sleep 1; done
```

Expect only `200`s. Any `502`/`503` means the ALB sent traffic to a pod that had already stopped.

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
