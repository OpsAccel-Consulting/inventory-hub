# Deployer access: a least-privilege identity for day-to-day runs

The one-time setup in the README needs an admin profile. After that, `make env-up` and `make env-down` can run as a separate IAM user, `inventory-deployer`, that holds only the permissions this project uses. Keep the admin profile for setup and break-glass fixes.

The two policies live in [`infra/iam/`](../infra/iam):

| File | Covers | Scoped to |
|---|---|---|
| `deployer-iam-policy.json` | Project IAM roles and their policies, the GitHub OIDC provider, service-linked roles | Roles named `inventory-hub-*`; only the AWS managed policies the Terraform attaches; roles can be passed only to EKS, EC2, EKS Pod Identity and VPC Flow Logs |
| `deployer-infra-policy.json` | VPC, EKS, RDS, Secrets Manager, KMS, CloudWatch Logs, ECR, SSM parameters, the state bucket, lookups made by the scripts | `inventory-hub-*` names where the service supports it, the KMS key by its `Project=inventory-hub` tag, everything else by region (`ap-south-1`) |

Two policies because one policy is limited to 6,144 characters. Neither contains an account ID: ARNs use `*` in the account field.

> **Not yet least-privilege.** The Terraform pipeline role is still given `AdministratorAccess`, so the IAM policy has to allow attaching it. Anyone holding these policies can therefore create an admin role. Once the pipeline role gets its own scoped policy, remove `AdministratorAccess` from the `AttachOnlyTheManagedPoliciesTheCodeUses` statement.

## Prerequisites

- The one-time setup in the README is done (state bucket, `configure-github.sh`).
- AWS CLI **2.32 or later** (for `aws login`): `aws --version`.
- An admin profile that is signed in. The examples use `inventory-admin`.

## 1. Check the policies

Run from the repository root:

```bash
export AWS_PROFILE=inventory-admin

for f in infra/iam/deployer-iam-policy.json infra/iam/deployer-infra-policy.json; do
  echo "== $f"
  aws accessanalyzer validate-policy --policy-type IDENTITY_POLICY \
    --policy-document "file://$f" \
    --query 'findings[].[findingType,issueCode]' --output table
done
```

`ERROR` findings must be fixed. `SECURITY_WARNING` and `SUGGESTION` findings are worth reading; the `iam:PassRole` and `AdministratorAccess` warnings are expected (see the note above).

## 2. Create the policies and the user

```bash
export AWS_PROFILE=inventory-admin
ACCT=$(aws sts get-caller-identity --query Account --output text)   # kept in a variable, never printed

aws iam create-policy --policy-name InventoryHubDeployer-IAM \
  --policy-document file://infra/iam/deployer-iam-policy.json --query Policy.PolicyName
aws iam create-policy --policy-name InventoryHubDeployer-Infra \
  --policy-document file://infra/iam/deployer-infra-policy.json --query Policy.PolicyName

aws iam create-user --user-name inventory-deployer --query User.UserName

aws iam attach-user-policy --user-name inventory-deployer \
  --policy-arn "arn:aws:iam::${ACCT}:policy/InventoryHubDeployer-IAM"
aws iam attach-user-policy --user-name inventory-deployer \
  --policy-arn "arn:aws:iam::${ACCT}:policy/InventoryHubDeployer-Infra"

# Lets the user sign in to the CLI with `aws login` (console credentials, no access keys)
aws iam attach-user-policy --user-name inventory-deployer \
  --policy-arn arn:aws:iam::aws:policy/SignInLocalDevelopmentAccess

# Confirm: three policies
aws iam list-attached-user-policies --user-name inventory-deployer \
  --query 'AttachedPolicies[].PolicyName' --output table
```

The user gets **no access keys**. It signs in through the browser like the admin profile, and the CLI rotates its temporary credentials automatically.

## 3. Turn on console sign-in and MFA

In the IAM console: **Users → inventory-deployer → Security credentials**

1. **Enable console access**, set a password (no need to force a reset if only you use it).
2. **Assign MFA device** and register it.

Optional, recommended if you record your screen: the browser sign-in page shows the account ID unless you sign in with an account alias.

```bash
aws iam create-account-alias --account-alias <your-alias>   # e.g. opsaccel-lab; must be globally unique
```

Then sign in at `https://<your-alias>.signin.aws.amazon.com/console`.

## 4. Set up the profile on your machine

```bash
aws login --profile inventory-deployer
#   region: ap-south-1
#   browser opens → "Continue with Root or IAM user" → sign in as inventory-deployer (+ MFA)

# Check who you are (account ID masked)
aws sts get-caller-identity --profile inventory-deployer --query Arn --output text \
  | sed -E 's/[0-9]{12}/<redacted>/g'
# expected: arn:aws:iam::<redacted>:user/inventory-deployer
```

`aws login` writes a `login_session` line containing the account ID to `~/.aws/config`. Don't open that file on camera.

The session lasts up to 12 hours; run `aws login --profile inventory-deployer` again when it expires.

## 5. Use it

```bash
export AWS_PROFILE=inventory-deployer
make env-up
make env-down
```

Or pass the profile explicitly: `./scripts/env-up.sh --profile inventory-deployer`.

**kubectl access.** The EKS cluster gives admin access to the identity that creates it. When `inventory-deployer` runs `env-up`, it creates the cluster and kubectl works. If a cluster created by another identity is still running, `kubectl` returns `Unauthorized` for the deployer: run `make env-down` with the profile that created it, or add the deployer's ARN to `cluster_admin_arns` in Terraform.

## 6. When something is denied

A policy written from the code can miss a call the Terraform AWS provider makes in the background. A denial looks like this:

```
AccessDenied: User: arn:aws:iam::<redacted>:user/inventory-deployer is not authorized
to perform: ec2:DescribeSomething on resource: ...
```

1. Note the action (`ec2:DescribeSomething`) and the resource.
2. Add the action to the matching statement in `infra/iam/deployer-*-policy.json`.
3. Publish a new version of the policy (as the admin profile). AWS keeps up to 5 versions; delete the oldest first if needed:

   ```bash
   aws iam create-policy-version \
     --policy-arn "arn:aws:iam::${ACCT}:policy/InventoryHubDeployer-Infra" \
     --policy-document file://infra/iam/deployer-infra-policy.json --set-as-default \
     --query PolicyVersion.VersionId
   ```

4. Re-run the same `make` target. Terraform continues from where it stopped.

Mask errors before sharing them: `... 2>&1 | sed -E 's/[0-9]{12}/<redacted>/g'`.

If the gaps are hard to pin down, turn on a CloudTrail trail (multi-region, management events), run one full `env-up`/`env-down` as the deployer, then use **IAM Access Analyzer → Generate policy** on `inventory-deployer` to see every action it called.

## Removing the deployer

```bash
export AWS_PROFILE=inventory-admin
ACCT=$(aws sts get-caller-identity --query Account --output text)

aws iam delete-login-profile --user-name inventory-deployer
# remove the MFA device in the console first (Security credentials → MFA)
for p in "arn:aws:iam::${ACCT}:policy/InventoryHubDeployer-IAM" \
         "arn:aws:iam::${ACCT}:policy/InventoryHubDeployer-Infra" \
         arn:aws:iam::aws:policy/SignInLocalDevelopmentAccess; do
  aws iam detach-user-policy --user-name inventory-deployer --policy-arn "$p"
done
aws iam delete-user --user-name inventory-deployer
```

Delete the two customer-managed policies afterwards if you no longer need them (non-default versions must be deleted first).
