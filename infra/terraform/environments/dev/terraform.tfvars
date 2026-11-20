# dev environment - non-production settings (low cost, easy to tear down)
project     = "inventory-hub"
environment = "dev"
region      = "ap-south-1"

# >>> Change these to your GitHub org/user and repository <<<
github_org  = "your-github-org"
github_repo = "inventory-hub"

# Numeric GitHub ID of the org/user above (public, not a secret):
#   gh api orgs/<github_org> --jq .id      (personal account: gh api users/<user> --jq .id)
# Needed when GitHub's OIDC token uses the ID form:
#   repo:<org>@<org-id>/<repo>@<repo-id>:...
github_owner_id = ""

# Set to false if the GitHub OIDC provider already exists in the account
create_github_oidc_provider = true

kubernetes_version  = "1.35"
node_instance_types = ["t3.medium"]
node_desired_size   = 2

db_instance_class      = "db.t4g.micro"
db_multi_az            = false
db_deletion_protection = false
db_skip_final_snapshot = true

# Restrict the EKS API to your office/VPN IP range:
# eks_public_access_cidrs = ["203.0.113.10/32"]
