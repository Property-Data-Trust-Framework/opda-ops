# opda-ops

Shared operations repo for the OPDA platform. Contains:

- **Terraform** — one-time AWS account bootstrap (S3 state bucket, OIDC provider)
- **Scripts** — bootstrap and manage API repos from zero to deployed
- **Templates** — `dotnet new` template for new OPDA API repos
- **Docs pipeline** — `docs-pdf/` builds the onboarding PDF from the wiki

---

## Documentation & PDF pipeline

The living documentation is the **GitHub wiki** (Runbook, Key-Learnings, ADRs,
Production-Readiness, cheatsheets) — it's the source of truth and survives the AWS
account being torn down. The wiki is itself a git repo: `git clone
https://github.com/Property-Data-Trust-Framework/opda-ops.wiki.git` is a full backup.

- **PDF pipeline** (how the onboarding PDF is built + published): [`docs-pdf/README.md`](docs-pdf/README.md)
- **Build the PDF locally** (cross-platform): [`docs-pdf/BUILDING.md`](docs-pdf/BUILDING.md)
- **Making this repo/wiki public**: [`PUBLISHING.md`](PUBLISHING.md)

---

## One-time Terraform bootstrap

Creates the shared infrastructure that all other repos depend on before they can use remote state or CI/CD.

| Resource | Name |
|---|---|
| S3 state bucket | `ops-terraform-state-<account-id>` |
| GitHub Actions OIDC provider | `https://token.actions.githubusercontent.com` |

The bucket has `prevent_destroy = true`. Deleting it would orphan state files for every repo — don't. State locking uses S3 native lockfiles (`use_lockfile = true`, Terraform ≥ 1.10); the old `ops-terraform-state-lock` DynamoDB table has been removed.

### Usage

```bash
aws configure  # or export AWS_* env vars
terraform init
terraform apply -var="github_org=Property-Data-Trust-Framework"
```

### Variables / Outputs

| Name | Description |
|---|---|
| `aws_region` | AWS region (default `eu-west-2`) |
| `github_org` | GitHub org owning the repos |

| Output | Description |
|---|---|
| `state_bucket_name` | S3 bucket name for per-API `backend.tf` |
| `github_oidc_provider_arn` | ARN of the shared OIDC provider |
| `account_id` | AWS account ID |

---

## Scripts

All scripts are run from the `opda-ops` repo root. They are designed to be run in order when bootstrapping a new API repo.

### `scripts/bootstrap-api.sh`

Creates a new OPDA API repo end-to-end: GitHub repo, local clone, submodule, scaffolding, `.NET` project, GitHub Actions environment and variables, and optional IAM bootstrap.

```bash
./scripts/bootstrap-api.sh [<repo-name>] [--skip-iam-bootstrap]
```

Prompts for repo name and base namespace if not supplied. Namespace defaults to PascalCase of the repo name (e.g. `opda-uprn-validator` → `OpdaUprnValidator`).

**Prerequisites:** `gh`, `aws`, `dotnet 9`, `git`, `terraform` (optional — IAM step skipped if absent or `--skip-iam-bootstrap` passed)

**What it does:**
1. Creates `Property-Data-Trust-Framework/<repo-name>` on GitHub (private)
2. Clones locally into `<repo-name>/`
3. Adds `opda-shared-services` as a git submodule
4. Copies scaffolding (workflows, terraform, openapi, bruno, keys skeleton)
5. Installs and runs `dotnet new opda-api -n <Namespace>`
6. Creates the `dev` GitHub Actions environment and sets all resolvable variables
7. Runs IAM bootstrap via Terraform (`aws_iam_role.github_actions`)

After it completes, follow the printed checklist: drop in Raidiam certs, run `normalise-certs.sh`, run `setup-secrets.sh`, then push to main.

---

### `scripts/normalise-certs.sh`

Renames Raidiam's GUID-named cert files to canonical names expected by the pipeline and Bruno.

```bash
./scripts/normalise-certs.sh --keys-dir <repo>/keys
```

Processes four folders:

| Folder | Canonical names |
|---|---|
| `server/transport/` | `transport.crt`, `transport.key` |
| `server/signing/` | `signing.key` |
| `client/transport/` | `transport.crt`, `transport.key` |
| `client/signing/` | `signing.key` |

Aborts if more than one non-canonical file is found in a folder (ambiguous which to use). Ignores `.csr` files.

---

### `scripts/setup-secrets.sh`

Pushes cert-based secrets to GitHub and wires up the Bruno environment. Run once after `bootstrap-api.sh` and `normalise-certs.sh`.

```bash
./scripts/setup-secrets.sh <repo-name> <client-id>
```

Both args are required (will prompt if omitted).

Pushes four GitHub secrets to the `dev` environment:

| Secret | Source |
|---|---|
| `TRANSPORT_CERTIFICATE` | `keys/server/transport/transport.crt` |
| `TRANSPORT_KEY` | `keys/server/transport/transport.key` |
| `SIGNING_KEY` | `keys/server/signing/signing.key` |
| `OAUTH_CLIENT_ID` | CLI arg |

Then calls `prepare-bruno-env.sh` to read the NLB hostname from Terraform and write `scripts/bruno.env`.

---

### `scripts/prepare-bruno-env.sh`

Reads `nlb_hostname` from Terraform output and prompts for the consumer client ID, then writes `scripts/bruno.env`. Requires Terraform/AWS access. Share the resulting file with developers.

From `opda-ops` (passing the target repo):
```bash
./scripts/prepare-bruno-env.sh --repo-dir <path>
```

From within the API repo:
```bash
./scripts/prepare-bruno-env.sh
```

---

### `scripts/apply-bruno-env.sh`

Patches `bruno/environments/aws.bru` and `bruno/bruno.json` using values from `scripts/bruno.env`. Does not require Terraform or AWS access — developers can run this after receiving `scripts/bruno.env` from a team member.

From `opda-ops` (passing the target repo):
```bash
./scripts/apply-bruno-env.sh --repo-dir <path>
```

From within the API repo:
```bash
./scripts/apply-bruno-env.sh
```

---

### `scripts/setup-github-env.sh`

Lower-level script to (re-)configure a GitHub Actions environment with secrets and variables. Used for managing existing repos rather than bootstrapping new ones.

```bash
./scripts/setup-github-env.sh [--repo <org/repo>] [--new-repo-name <name>] [--dry-run]
```

Reads values from `scripts/.env.<env>` (default `dev`). Copy `scripts/.env.example` to get started.

---

## Templates

### `templates/dotnet/`

A `dotnet new` installable template for scaffolding new OPDA API repos.

**Template:** `templates/dotnet/template/`  
Short name: `opda-api`  
Source name substitution: `MyApi` → your namespace (set via `-n`)

```bash
dotnet new install ./templates/dotnet/template
dotnet new opda-api -n OpdaUprnValidator --output .
```

Generates:
- `src/<Namespace>/Program.cs` — minimal API with `/health` endpoint, Lambda hosting
- `tests/<Namespace>.Tests/HealthTests.cs` — `WebApplicationFactory` integration test
- `<Namespace>.sln`, `Dockerfile`, `docker-compose.yml`

**Scaffolding:** `templates/dotnet/scaffolding/`  
Copied verbatim into the new repo by `bootstrap-api.sh`:

| Path | Contents |
|---|---|
| `.github/workflows/deploy.yml` | Full CI/CD pipeline: test → ECR → IAM → build/push → Terraform apply |
| `terraform/` | Complete modular Terraform: VPC, mTLS proxy, authorizer, API Gateway, Lambda, ECR, IAM, SSM |
| `openapi/api.yml` | OpenAPI stub with health endpoint and Lambda ARN placeholders |
| `bruno/` | API collection with `aws` environment, mTLS cert config, Get Token + Get Health requests |
| `keys/` | Folder structure with `.gitkeep` files; `keys/ca/ca_trusted_list.pem` pre-populated |

**Keys folder structure:**

```
keys/
  raidiam/
    ca/
      ca_trusted_list.pem   ← Raidiam OPDA Sandbox PKI bundle (committed — public)
    server/
      transport/            ← Drop server transport.crt + transport.key here
      signing/              ← Drop server signing.key here
    client/
      transport/            ← Drop client transport.crt + transport.key here (Bruno mTLS)
      signing/              ← Drop client signing.key here (Bruno Get Token JWT)
```

Private keys and certs are gitignored. Only `.gitkeep` files and the CA bundle are committed.

---

## Full workflow: zero to deployed + Bruno

```
1. bootstrap-api.sh <repo-name>
   └─ creates repo, scaffolding, dotnet project, GH env vars, IAM role

2. Download Raidiam certs → drop into keys/ subfolders

3. normalise-certs.sh --keys-dir <repo>/keys
   └─ renames GUID files to canonical names

4. setup-secrets.sh <repo-name> <client-id>
   └─ pushes TRANSPORT_CERTIFICATE, TRANSPORT_KEY, SIGNING_KEY, OAUTH_CLIENT_ID to GitHub
   └─ patches Bruno aws.bru with baseUrl + clientId

5. git push main
   └─ pipeline: test → build → terraform apply → deploy Lambda

6. In Bruno:
   - Enable developer mode: Preferences → General → Enable Developer Mode (required for Web Crypto)
   - Open the collection, select the 'aws' environment
   - Set the `signingKey` secret to the contents of `keys/client/signing/signing.key`
     (this is a Bruno secret variable — it is never persisted to disk and must be re-entered each session)
   - Run Get Token, then make API calls
```

Steps 4 and 5 may need to be repeated once after the first deploy: `prepare-bruno-env.sh` reads the NLB hostname from Terraform output, which only exists after the first successful apply.

---

## Tearing down an API repo

### Normal teardown (Terraform state intact)

Run locally — there is no destroy workflow in CI.

Credential and image-tag variables default to `""` so only the three structural variables need to be supplied:

```bash
cd <repo-name>/terraform
terraform init -backend-config="key=<repo-name>/dev/terraform.tfstate"
TF_VAR_name="<repo-name>" \
TF_VAR_environment="dev" \
TF_VAR_github_repo="Property-Data-Trust-Framework/<repo-name>" \
terraform destroy
```

Then clean up the orphaned state file and delete the GitHub repo:

```bash
BUCKET="ops-terraform-state-$(aws sts get-caller-identity --query Account --output text)"
aws s3 rm "s3://${BUCKET}/<repo-name>/dev/terraform.tfstate"
gh repo delete Property-Data-Trust-Framework/<repo-name> --yes
```

**Known gotchas:**

- **Lambda ENIs** — AWS can take 15–20 minutes to detach a Lambda's VPC network interfaces after the function is deleted. If `terraform destroy` times out waiting for VPC deletion, wait a few minutes and re-run — it will pick up where it left off.
- **ECS service drain** — Terraform scales the ECS service to 0 tasks before deleting it. This takes a minute or two; the destroy will wait automatically.
- **GitHub Actions IAM role** — the role is destroyed along with everything else. This is fine; the destroy operation is already authenticated before the role is removed.
- **Shared resources are unaffected** — the `opda-ops` S3 state bucket, OIDC provider, and `opda-shared-services` ECR images all survive.

---

### Manual teardown (Terraform state corrupted or lost)

Delete resources in this order to respect dependencies. Replace `<name>` with the repo name (e.g. `opda-template-test-one`).

**1. API Gateway**
- REST API named `<name>` (deletes stages and deployments with it)

**2. Lambda functions**
- `<name>` (app Lambda)
- `<name>-authorizer`

**3. ECS**
- Service: `<name>-service` (in cluster `<name>-cluster`) — scale to 0 first, then delete
- Cluster: `<name>-cluster`
- Task definition: deregister all revisions of `<name>-mtls` (or similar prefix)

**4. NLB**
- Load balancer: `<name>`
- Target group: `<name>-mtls-tg`

**5. ECR**
- Repository: `<name>` (delete images first, or tick "Delete repository" which purges them)

**6. SSM parameters** (all under `/<name>/`)
- `/<name>/transport_certificate`
- `/<name>/transport_key`
- `/<name>/ca_trusted_list`
- `/<name>/signing_key`

**7. IAM roles and policies** (inline policies are deleted with the role)
- `<name>-github-actions`
- `<name>-lambda`
- `<name>-authorizer-role`
- `<name>-ecs-task-execution-role`
- `<name>-apigw-logging-role`

**8. CloudWatch log groups**
- `/aws/lambda/<name>` (app Lambda)
- `/aws/lambda/<name>-authorizer`
- `/aws/apigateway/<name>-access-logs`
- `/ecs/<name>-mtls`

**9. VPC and networking** — wait until Lambda and ECS ENIs are fully detached before deleting (can take 15–20 minutes after step 2–3)
- Security groups: `<name>-nlb-sg`, `<name>-ecs-sg`, `<name>-authorizer-sg`, `<name>-lambda`, `<name>-vpc-endpoints-sg`
- VPC endpoints: all endpoints attached to the `<name>` VPC (execute-api, ssm, ssm-messages, kms, ecr.api, ecr.dkr, logs, s3)
- NAT Gateway (release the associated Elastic IP once it is deleted)
- Internet Gateway (detach from VPC first)
- Route tables, subnets, VPC — delete in that order

**10. Route53** (only if a custom domain was configured)
- A record: `matls-<name>.<domain>`

**11. Elastic IP**
- Any unassociated EIPs created for the NAT Gateway

**12. GitHub**
- Delete the repo — this removes all secrets, variables, and environments with it

**13. S3 state file**
- `s3://ops-terraform-state-<account-id>/<name>/dev/terraform.tfstate`
