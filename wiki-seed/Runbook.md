# Runbook

Operational procedures for the OPDA API family. Covers standard deploys, rotations, teardowns, and verification.

For **why** any of this is the way it is, see [[Key-Learnings]] and the [[Decisions]] (ADRs).

> **Convention:** every multi-step CLI invocation is reproduced in the per-tool cheatsheet ([[Cheatsheet-AWS]], [[Cheatsheet-GH]], [[Cheatsheet-Terraform]]) as a single-line command for easy paste. Multi-line examples in this file are illustrative — use the cheatsheet for execution.

---

## Environment / account

| | |
|---|---|
| AWS account | `<AWS_ACCOUNT_ID>` |
| Region | `eu-west-2` |
| State bucket | `ops-terraform-state-<AWS_ACCOUNT_ID>` |
| State locking | S3 native (`use_lockfile = true`, TF 1.10.5) |
| GitHub org | `Property-Data-Trust-Framework` |

---

## Repo topology

| Repo | Role |
|---|---|
| `opda-ops` | One-time bootstrap: state bucket, OIDC, shared VPC, scaffolding, scripts |
| `opda-shared-infra` | Reusable Terraform modules (`vpc`, `mtls-proxy`, `authorizer`, `api-gateway`) |
| `opda-shared-services` | Go binaries: mTLS proxy + Lambda authorizer; publishes images to shared ECR |
| `opda-lr-facade` | HMLR SOAP facade (Go) |
| `opda-uprn-validator` | UPRN format validation (.NET) |
| `opda-mra-api` | Mining-remediation / coalfield lookup (.NET, DynamoDB) |
| `opda-os-api` | OS Places API proxy (.NET) |
| `opda-council-tax-api` | Council tax band lookup (.NET, DynamoDB) |
| `opda-epc-api` | EPC domestic search (.NET, DynamoDB) |
| `opda-survey-shack-api` | Survey document retrieval (.NET, DynamoDB + S3) |
| `opda-armalytix-api` | Armalytix partner integration (.NET) |
| `opda-smoove-api` | Smoove partner integration (.NET) |
| `opda-competition-api` | Hackathon API — UPRN validation + provenance (.NET, custom domain `opda.info`) |

**Push order whenever changes touch multiple repos:** `opda-shared-services` → `opda-shared-infra` → API repo. See [[Key-Learnings]] "Terraform / CI ordering".

### Where to run commands

Check the repos out **side by side under a common parent directory** (the workspace root). Then:

- **Per-repo commands** (e.g. `./scripts/normalise-certs.sh`, `./scripts/prepare-bruno-env.sh`, `./scripts/teardown.sh`, `terraform` in `terraform/`) run from **that repo's own root**.
- **`opda-ops` orchestration scripts** (`bootstrap-api.sh`, `setup-secrets.sh`, `setup-github-env.sh`, `setup-shared-services.sh`) **create and act on sibling repos**, so they run from the **workspace root** (the parent that contains `opda-ops/` and its siblings) — shown below as `./opda-ops/scripts/…`. This is by design; the scripts' own headers note it.

---

## Standard deploy of an existing service

1. Push to `main`.
2. CI runs `test → ECR build/push → terraform apply → Lambda deploy`.
3. If the **shared proxy TLS cert** changed (i.e. you re-ran `deploy-shared-proxy.sh`), force an ECS restart so the proxy reloads it — see "Force ECS restart for cert reload" below. Per-API Lambda certs (transport, signing, CA, dataprov) are read by the Lambda on each invocation — no restart needed.
4. Verify with the service's Bruno collection.

---

## First-time account bootstrap

For the very first deploy in a fresh AWS account. Subsequent API repos use "Bootstrapping a new API repo" below — this section covers what `opda-ops` and `opda-shared-services` need before any of that works.

Prerequisites:
- AWS CLI configured with admin credentials for `<AWS_ACCOUNT_ID>`
- `gh` CLI installed and authenticated
- Terraform 1.10.5+ installed
- `opda-ops` already bootstrapped (S3 state bucket, OIDC provider, shared VPC) — see `opda-ops/README.md`

### Bootstrap `opda-shared-services` (one-time per account)

Creates the shared ECR repo and the GitHub Actions IAM role for the publish pipeline:

```
cd opda-shared-services/terraform && terraform init -backend-config="key=opda-shared-services/terraform.tfstate" && terraform apply
```

Wire up the GitHub Actions environment (the script reads the role ARN from AWS — no copy-paste):

```
./opda-ops/scripts/setup-shared-services.sh
```

Push `opda-shared-services` to `main`. The publish pipeline builds both Docker images and pushes them to ECR.

### Bootstrap the first API repo

For `opda-lr-facade` (or any first-of-a-kind API). Creates the per-repo ECR repo and GitHub Actions IAM role:

```
cd opda-lr-facade/terraform && terraform init -backend-config="key=opda-lr-facade/dev/terraform.tfstate" && terraform apply
```

Then populate `.env.dev` from the example file. **Auto-resolved from AWS** by `setup-github-env.sh` (leave blank unless overriding):

| Variable | Resolved from |
|---|---|
| `GH_SECRET_AWS_ROLE_ARN` | IAM role `<repo>-github-actions` |
| `GH_VAR_SHARED_SERVICES_ECR_BASE` | ECR `opda-shared-services` |
| `GH_VAR_AUTHORIZER_IMAGE_TAG` | latest `authorizer-*` SHA in ECR |

**Manual values** (must be filled in):

| Variable | What it is |
|---|---|
| `GH_SECRET_OAUTH_CLIENT_ID` | OAuth2 client ID URL (Raidiam-issued — full URL form) |
| `GH_VAR_OAUTH_ISSUER` | OAuth2 issuer URL — no trailing slash |
| `GH_SECRET_TRANSPORT_CERTIFICATE` | PEM — Raidiam-issued provider client cert (used by the authorizer Lambda for outbound mTLS to Raidiam's token introspection endpoint) |
| `GH_SECRET_TRANSPORT_KEY` | PEM — private key for above |
| `GH_SECRET_CA_TRUSTED_LIST` | PEM bundle — CAs trusted for incoming client cert verification |
| `GH_SECRET_HMLR_USERNAME` / `GH_SECRET_HMLR_PASSWORD` | HMLR Business Gateway creds (facade only) |
| `GH_VAR_HMLR_ENDPOINT` | HMLR Business Gateway SOAP endpoint |
| `GH_SECRET_HMLR_CLIENT_CERT` / `GH_SECRET_HMLR_CLIENT_KEY` | PEM — mTLS client cert/key for HMLR (facade only) |
| `GH_VAR_PROVENANCE_SIGNING_KID` | Raidiam-issued KID for the provenance signing cert (separate cert from the rtssigning cert used for `private_key_jwt` AuthN). Public — variable, not secret. Empty disables signing — responses are returned as the unsigned PDTF v3.5 propertyPack (same body, minus the `{data, provenance}` envelope). |
| `GH_SECRET_DATAPROV_KEY` | PEM — RSA private key paired with the KID above. Maps to `TF_VAR_dataprov_key` in `deploy.yml`. Public half is auto-published in our org's hosted JWKS at `keystore.directory.pdtf.raidiam.io/{org-id}/application.jwks` — no separate JWKS endpoint to stand up. |

Then run:

```
source opda-ops/scripts/.env.dev && ./opda-ops/scripts/setup-github-env.sh --repo Property-Data-Trust-Framework/opda-lr-facade --env dev --no-submodules
```

The script prints what it resolved from AWS and what it read from the env file before setting anything — eyeball it before letting it write.

Push to `main` to trigger the deploy. The pipeline builds the facade image, pushes to ECR, then `terraform apply`s the full stack in one shot. Live mTLS endpoint lands at `https://matls-opda-lr-facade.<EXTERNAL_DOMAIN_NAME>` (or the raw NLB DNS if no Route53 zone is wired).

---

## Bootstrapping a new API repo

The end-to-end path (assumes `opda-ops` already bootstrapped and `opda-shared-services` images exist in ECR):

Set the repo name once before running any of the commands below:
```bash
REPO=opda-<api>   # e.g. REPO=opda-epc-api
```

1. From workspace root:
   ```bash
   ./opda-ops/scripts/bootstrap-api.sh $REPO
   ```
   Creates the GitHub repo, scaffolds files, adds `opda-shared-services` submodule, makes the initial commit using your global git identity, derives the Bruno collection name from the repo name. The script prints a full checklist on completion — follow it.

2. Download Raidiam certs and drop into the correct subfolders:
   ```
   $REPO/keys/server/transport/   ← Raidiam rtstransport cert + key (unique per API — used by authorizer for outbound Raidiam auth)
   $REPO/keys/server/signing/     ← server signing key (rtssigning — unique per API, matches the registered client ID)
   $REPO/keys/server/provenance/  ← provenance cert + key (dataprov — unique per API, generate separately in Raidiam portal)
   $REPO/keys/client/transport/   ← client transport cert + key (shared consumer identity — copy from any existing API repo)
   $REPO/keys/client/signing/     ← client signing key (shared consumer identity — copy from any existing API repo)
   $REPO/keys/ca/                 ← CA trusted list (shared — copy from any existing API repo)
   ```
   Each API must have its **own** Raidiam application registration — the server signing key must match the registered client ID or introspection will fail. The client keys are the consumer identity used by Bruno and are the same across all APIs.
   The KID the Raidiam portal issues for the provenance cert is the `PROVENANCE_SIGNING_KID` GitHub variable.

   > **`keys/server/tls/`** — not needed for shared-proxy APIs (all APIs live under `dev.api.smartpropdata.org.uk` which has a wildcard Let's Encrypt cert managed by the shared proxy). Only populate this folder if you are setting up a standalone API with its own custom domain.

3. Normalise the GUID-named cert files to canonical names:
   ```bash
   cd $REPO && ./scripts/normalise-certs.sh
   ```

4. Apply per-repo IAM (separate state, lives in `terraform/iam/`):
   ```bash
   BUCKET="ops-terraform-state-$(aws sts get-caller-identity --query Account --output text)"
   cd $REPO/terraform/iam && terraform init -reconfigure -backend-config="bucket=$BUCKET" -backend-config="region=eu-west-2" -backend-config="key=$REPO/iam/terraform.tfstate" && terraform apply
   ```
   > The IAM state and the main stack state are completely separate — re-applying IAM never touches deployed API resources.

5. Populate GitHub Actions secrets/variables for the `dev` environment:
   ```bash
   ./opda-ops/scripts/setup-secrets.sh $REPO <provider-client-id> [<provenance-kid>]
   ```
   > **Provider client ID is unique per API** — use the client ID URL from the specific Raidiam application registration for this repo (e.g. `https://rp.directory.pdtf.raidiam.io/openid_relying_party/<uuid>`). Do not copy it from another API.

6. Push to `main` to trigger the first deploy.

7. Once deployed, prepare the Bruno env (chains into `apply-bruno-env.sh`):
   ```bash
   cd $REPO && ./scripts/prepare-bruno-env.sh --environment dev
   ```

8. Verify with Bruno (see "Token + Bruno verify" below).

9. Add the new API to the docs site:
   - Add an entry to `opda-ops/api-docs/src/App.tsx` (url, title, slug)
   - Run `./deploy-api-docs.sh` from the workspace root

---

## Token + Bruno verify

Bearer tokens from Raidiam expire after ~5 minutes — re-run Get Token on every 401.

1. Open the API repo's Bruno collection. Confirm:
   - Developer mode enabled — **must be re-enabled each Bruno session** (Preferences → General → Enable Developer Mode)
   - `signingKey` secret set to the contents of `keys/client/signing/signing.key` — persists between sessions, only needs setting once per machine
   - Client cert picked up automatically from `apply-bruno-env.sh` — no manual UI configuration needed
   - Auth set at **collection** level; requests inherit
   - `baseUrl` has **no trailing slash**

2. Run the `Get Token` request in Bruno. It builds the `private_key_jwt` assertion using `signingKey`, calls Raidiam's mTLS token endpoint, and stores the result as `bearerToken` automatically.

3. Send the API request. On a fresh deploy of `opda-mra-api` exercise all four scenarios (ON, OFF, UNKNOWN, invalid). For `opda-os-api` use `query=capel+isaac,sa43jq&maxresults=1`.

> **LR facade only:** an internal helper script (`raidiam-script.sh`, kept locally — not part of the public repos) hardcodes the facade's NLB URL and register-extract POST body and calls the API directly. It is not a general token utility.

If client-cert configuration is lost on Bruno reload, you've probably re-introduced a `clientCertificate { ... }` block in a `.bru` env file — see [[Key-Learnings]] "Bruno". Don't.

---

## Force ECS restart for cert reload

The shared proxy reads SSM at container startup. Terraform won't recycle ECS tasks when only SSM **values** change (e.g. after rotating the shared proxy's TLS cert via `deploy-shared-proxy.sh`).

```
aws ecs update-service --cluster opda-shared-proxy-dev-cluster --service opda-shared-proxy-dev-service --force-new-deployment --region eu-west-2
```

Wait for new tasks to reach `RUNNING` before testing (shared proxy runs 2 tasks).

> **Per-API Lambda certs** (transport, signing, CA, dataprov) do **not** require an ECS restart — the authorizer Lambda reads them from SSM on every invocation.

---

## Cert / credential rotation

GitHub Actions secrets are the master copy; Terraform writes to SSM on every deploy. **Direct SSM updates are the P1 escape hatch** — they will be overwritten by the next deploy unless the GitHub secret is also updated.

P1 (escape hatch — values not paths):
```
aws ssm put-parameter --name /opda-lr-facade-dev/transport_certificate --value "$(cat keys/server/transport/transport.crt)" --type String --overwrite --region eu-west-2
aws ssm put-parameter --name /opda-lr-facade-dev/transport_key --value "$(cat keys/server/transport/transport.key)" --type SecureString --overwrite --region eu-west-2
aws ssm put-parameter --name /opda-lr-facade-dev/ca_trusted_list --value "$(cat keys/ca/ca_trusted_list.pem)" --type String --overwrite --region eu-west-2
```

Parameter naming convention: `/<name>-<environment>/<param>` (e.g. `/opda-lr-facade-dev/signing_key`). All SSM params follow this pattern.

**After updating per-API Lambda certs** (transport, signing, CA, dataprov) via SSM: no ECS restart needed — the authorizer Lambda reads SSM on each invocation. The next API call will use the new value.

**After updating the shared proxy TLS cert** (only via `deploy-shared-proxy.sh`): force an ECS restart — see "Force ECS restart for cert reload" above.

⚠️ The HMLR cert/key SSM resources in `opda-lr-facade/terraform/ssm.tf` do **not** currently have `lifecycle { ignore_changes = [value] }` — `terraform apply` will overwrite an out-of-band rotation. Update the GitHub secret in tandem with the SSM value, or add the lifecycle block (tracked in [[Production-Readiness]]). The `os_api_key` SSM resource in `opda-os-api` does have it.

---

## Migrating an API to a different Raidiam organisation

Use this when a service moves from one participant's org to another in the Raidiam Directory (e.g. from the OPDA sandbox org to the MRA org). The AWS account, domain, and infrastructure do not change — only the Raidiam identity.

### 1. Prepare the local key directory

```bash
cd <repo-root>
mv keys/server keys/server-old          # preserve old certs until migration is verified
mkdir -p keys/server/transport keys/server/signing keys/server/provenance
```

### 2. Register the service in the destination Raidiam org

In the Raidiam Directory UI:

1. **Add a server** to the destination organisation — set the API discovery endpoints using the standard OPDA base URL (`dev.api.smartpropdata.org.uk`).
2. **Add an application** to the organisation and upload the three certificates (generated via the standard CSR process):
   - **Transport cert** → `keys/server/transport/`
   - **Signing cert** → `keys/server/signing/`
   - **Provenance cert** → `keys/server/provenance/`

Download all three resulting `.pem` files into their respective folders.

### 3. Normalise cert filenames

The Raidiam portal gives certs GUID-prefixed filenames. Normalise them to canonical names:

```bash
# from the repo root
./scripts/normalise-certs.sh
```

### 4. Push new credentials to GitHub

```bash
REPO=<repo-name>   # e.g. opda-mra-api

# from the workspace root
./opda-ops/scripts/setup-secrets.sh $REPO <new-provider-client-id> [<new-provenance-kid>]
```

This updates `TRANSPORT_CERTIFICATE`, `TRANSPORT_KEY`, `SIGNING_KEY`, `DATAPROV_KEY`, `OAUTH_CLIENT_ID`, and `PROVENANCE_SIGNING_KID` in GitHub Actions. There is no need to re-run `prepare-bruno-env.sh` — the Bruno client credentials are the consumer-side OPDA certs and are unaffected by a server-side org migration.

### 5. Redeploy

Trigger a deploy to rotate the SSM parameters and Lambda config:

```bash
git commit --allow-empty -m "Trigger redeploy: Raidiam org migration"
git push
```

Or re-run the most recent workflow manually in GitHub Actions.

### Verification

- Hit `/health` via Bruno to confirm the Lambda starts cleanly with the new certs.
- Run `Get Token` then a real API call — a successful provenance-signed response confirms the new signing and provenance keys are wired correctly.

> **Note:** If `keys/server-old/` is no longer needed once verified, delete it — it contains private key material that should not persist unnecessarily.

---

## Service teardown

Each API repo has a `teardown.sh` with double confirmation (type `yes`, then the repo name).

```
./opda-<api>/scripts/teardown.sh
```

What it does:
- `terraform destroy` on the per-API stack
- Leaves the per-repo IAM state (in `terraform/iam/`) **intact** — that's deliberate, the role is shared across environments

Post-teardown verification — see [[Key-Learnings]] "AWS quirks":
- Lambda ENIs take 15–20 minutes to release; immediate "still-present" reports are false positives
- CloudWatch log groups can survive a failed destroy — check and clean up explicitly

Manual followups if needed:
- Delete the S3 state file: `aws s3 rm s3://ops-terraform-state-<AWS_ACCOUNT_ID>/opda-<api>/<env>/terraform.tfstate`
- Delete IAM state if you want to fully remove the repo: destroy from `terraform/iam/`

---

## DynamoDB data load — `opda-mra-api`

Coalfield CSV → DynamoDB batch write. Re-runnable; safe to repeat after CSV updates.

From the `opda-mra-api` repo root (the script takes **positional** args `<csv-file> <environment>`, not flags):

```
./scripts/import-coalfields.sh data/coalfields.csv dev
```

Targets table `opda-mra-api-coalfields-{environment}`. Source CSV: `data/coalfields.csv` (column 1 UPRN, column 2 `ON`/`OFF`).

The table itself is created via Terraform `data` source and IAM permits `dynamodb:GetItem` on it from the Lambda. Data is **not** managed by Terraform — population is operational, separate from infrastructure.

---

## OS API key (`opda-os-api`) wiring

```
gh secret set OS_API_KEY --body "<key>" --env dev --repo Property-Data-Trust-Framework/opda-os-api
gh variable set OS_API_BASE_URL --body "https://api.os.uk/" --env dev --repo Property-Data-Trust-Framework/opda-os-api
```

Verify the key independently before involving the OPDA stack — a standalone Bruno collection that hits `api.os.uk` directly with the key is kept for this.

---

## BYPASS_AUTH escape hatch

Useful only during initial bootstrap, before Raidiam certs are wired. **Default is `false` and should stay that way for any production-bound deploy.**

- GitHub Actions variable: `BYPASS_AUTH=true`
- Bruno `bearerToken` can be any non-empty string (API GW still requires the header to be present)
- Module default in `opda-shared-infra/modules/authorizer` is `false`, so this can never accidentally land in prod

Important caveat: with bypass on, the authorizer still runs — it skips introspection and cert-binding and injects a hard-coded `land-registry` scope into the authorizer context (`authorizer/main.go` `handleRequest`), so endpoints gating on `land-registry` (all current data APIs) work normally under bypass. Endpoints requiring a *different* scope still fail (only `land-registry` is present). Note the deployed authorizer is image-pinned (`AUTHORIZER_IMAGE_TAG`): an image predating the scope injection instead leaves `HttpContext.User` claimless, 401ing every scope-gated route. See [[Key-Learnings]] ".NET Lambda packaging".

---

## Local development

### Go facade (`opda-lr-facade`) — local development

The earlier LocalStack/docker-compose local stack no longer exists (no `docker-compose.yml`, `generate-dev-certs.sh`, `build-local.sh`, or Bruno `local` environment in the repo). Facade local dev is now:

1. Initialise the submodule:
   ```
   git submodule update --init --recursive
   ```
2. Build + test directly:
   ```
   go build . && go vet ./... && go test ./...
   ```
3. Mock mode: the deployed sandbox (and any local run) uses the `LOCAL_MOCK=true` env var (`internal/api/api.go`) to return a canned register extract instead of calling HMLR. The mock response is the PDTF v3.5 propertyPack — `data.propertyPack.titlesToBeSold[0].registerExtract.{ocSummaryData, ocRegisterData}` (camelCase); the old flat top-level `OCSummaryData`/`OCRegisterData` shape is gone.

End-to-end verification uses the Bruno collection's `aws` environment against the live mTLS endpoint (real Raidiam-issued certs + a fresh bearer token) — see "Token + Bruno verify". `bruno/register-extract/post-register-extract.bru` asserts the propertyPack shape.

### .NET APIs — gap

The .NET APIs (`opda-uprn-validator`, `opda-mra-api`, `opda-os-api`) currently have only a bare `docker-compose.yml` with the app container — no LocalStack, no mTLS proxy. Filling that gap is a deferred work item to be done across all .NET repos in one pass.

---

## Troubleshooting checklist

When a deploy completes but Bruno calls fail, work through these in order before digging into logs:

1. **`bearerToken` fresh?** Tokens expire in ~5 minutes — re-run `Get Token` in Bruno.
2. **Bruno cert domain matches URL?** `bruno.json` `clientCertificates[].domain` must be the **exact hostname** from the `baseUrl` (e.g. `dev.api.smartpropdata.org.uk`). A mismatch causes Bruno to silently not attach the cert — the proxy receives no `TLS-Certificate` header and the authorizer returns 401 with `no Tls-Certificate found on request`. Re-run `prepare-bruno-env.sh` + reload Bruno if you suspect a mismatch.
3. **Health check 200 ≠ cert working.** The proxy's `/health` handler responds before API Gateway is involved — a 200 health check only means the proxy is alive. It says nothing about whether Bruno is presenting its client cert.
4. **Bruno cert listed for every domain?** `clientCertificates` needs an entry for both the API endpoint hostname and `matls-auth.directory.pdtf.raidiam.io`.
5. **Bruno auth at collection level?** Requests should inherit, not declare their own `auth:bearer`.
6. **`baseUrl` clean?** No trailing slash.
7. **ECS task running with latest certs?** If you updated SSM, did you `--force-new-deployment`?
8. **Authorizer image SHA matches?** GitHub var `AUTHORIZER_IMAGE_TAG` must point at a published image in ECR. (`MTLS_PROXY_IMAGE_TAG` was removed from per-API repos post-shared-proxy migration — the shared proxy image tag is managed by `deploy-shared-proxy.sh` only.)
9. **CA trust list current?** If introspection is failing with `x509: signed by unknown authority`, the `CA_TRUSTED_LIST` secret may still be the dev CA. Replace with the OPDA CA from the Raidiam reference repo.
10. **Scope claim shape?** For .NET APIs, the scope filter reads `http.User.FindFirst("scope")` — not `HttpContext.Items`. With `BYPASS_AUTH=true` the (current) authorizer injects the `land-registry` scope, so endpoints gating on that scope pass; a 401 under bypass means the deployed authorizer image predates the scope injection (see "BYPASS_AUTH escape hatch").
11. **HMLR `messageId` numeric?** In the test environment, alphanumeric is silently rejected.
12. **Log groups** — `/aws/lambda/<name>`, `/aws/lambda/<name>-authorizer`, `/ecs/<name>-mtls`. Authorizer logs include masked claims; SOAP errors land in the facade Lambda log.

---

## Hackathon — `opda-competition-api`

Everything in this section is specific to the 2026-05-19 hackathon. The competition API is deliberately throwaway — tear it down cleanly after the event.

### What was built

| Component | Description |
|---|---|
| `POST /v1/winning-uprn` | Accepts a UPRN; first correct submission wins. Time-gated: rejects before 08:00 UTC 19 May 2026. |
| `GET /v1/competition-uprns` | Returns the list of eligible UPRNs (winning UPRN is in the list but not indicated). |
| DynamoDB `opda-competition-api-dev-winners` | One record per UPRN — conditional write ensures only the first submission persists. |
| DynamoDB `opda-competition-api-dev-eager-beavers` | Records clientIds that attempted before the competition opened (first attempt only). |
| DynamoDB `opda-competition-api-dev-attempts` | Records every valid-format UPRN attempt (PK: `client_id`, SK: `uprn`) — drives the "you've already tried this" message. |
| Leaderboard Lambda | Python 3.12 zip Lambda — reads winners + eager beavers tables, returns JSON. No VPC, no mTLS. |
| Leaderboard HTTP API Gateway | Public API Gateway HTTP API fronting the leaderboard Lambda. No auth. |
| Leaderboard S3 + CloudFront | Static microsite at `https://leaderboard.opda.info`. HTML is patched at deploy time with the API URL. |
| ACM certificate | `leaderboard.opda.info` — **lives in `us-east-1`** (CloudFront requirement). See teardown note below. |

### Competition management

Check who's in the eager beavers table:
```
aws dynamodb scan --table-name opda-competition-api-dev-eager-beavers --region eu-west-2
```

Check current winner:
```
aws dynamodb scan --table-name opda-competition-api-dev-winners --region eu-west-2
```

Check attempts for a specific client:
```
aws dynamodb query --table-name opda-competition-api-dev-attempts --key-condition-expression "client_id = :c" --expression-attribute-values '{":c":{"S":"<client-id>"}}' --region eu-west-2
```

Purge the winner (e.g. to clear test data before the event):
```
aws dynamodb delete-item --table-name opda-competition-api-dev-winners --key '{"uprn":{"S":"200001858581"}}' --region eu-west-2
```

Purge a specific eager beaver entry:
```
aws dynamodb delete-item --table-name opda-competition-api-dev-eager-beavers --key '{"client_id":{"S":"<client-id>"}}' --region eu-west-2
```

Check eager beaver UPRN submissions (CloudWatch Logs Insights on `/aws/lambda/opda-competition-api-dev`):
```
aws logs start-query --log-group-name /aws/lambda/opda-competition-api-dev --start-time $(date -d '7 days ago' +%s) --end-time $(date +%s) --query-string 'fields @timestamp, @message | filter @message like /Eager beaver/ | sort @timestamp asc' --region eu-west-2
```

### ⚠️ Teardown — ACM certificate in us-east-1

The leaderboard CloudFront distribution uses an ACM certificate for `leaderboard.opda.info`. **This certificate lives in `us-east-1`, not `eu-west-2`.** The standard `teardown.sh` script runs `terraform destroy` which will remove it, but if you ever need to check or manually clean up:

```
aws acm list-certificates --region us-east-1
aws acm delete-certificate --certificate-arn <arn> --region us-east-1
```

The Route53 validation records (`_acme-challenge`-style CNAME entries in `opda.info`) are also managed by Terraform and will be destroyed automatically.

### Post-hackathon teardown order

1. Run `teardown.sh` — destroys the full stack including DynamoDB tables, Lambda, API Gateway, S3 bucket, CloudFront distribution, and the ACM cert in us-east-1.
2. Verify the ACM certificate is gone: `aws acm list-certificates --region us-east-1`
3. Verify the `leaderboard.opda.info` Route53 record is gone (check in the hosted zone).
4. If the `opda.info` hosted zone itself is no longer needed, delete it and ask the domain admin to remove the NS records.
5. The Let's Encrypt cert for `*.opda.info` was stored locally — no AWS resource to clean up there.

---

## Major milestones (delivered)

In rough order, for orientation:

| Date | Milestone |
|---|---|
| 2026-04-14 | Dev smoke test — Bruno → AWS round-trip, mock HMLR response |
| 2026-04-14 | HMLR connectivity — real SOAP responses from `bgtest.landregistry.gov.uk` |
| 2026-04-17 | `private_key_jwt` authentication live; `BYPASS_AUTH=false` in production |
| 2026-04-20 | Bootstrap toolchain + `opda-template-test-one` deployed via `bootstrap-api.sh` |
| 2026-04-21 | `opda-uprn-validator` deployed and verified; both test repos torn down cleanly |
| 2026-04-21 | Shared-VPC migration complete; `-facade` suffix removed; per-repo IAM split |
| 2026-04-23 | `opda-mra-api` (coalfield) deployed and verified end-to-end with DynamoDB |
| 2026-04-25 | `opda-os-api` implementation complete (incl. mapped `PlaceResult`); pending push + Bruno verify |
| 2026-05-02 | Provenance signing live on `opda-uprn-validator` |
| 2026-05-10 | `opda-council-tax-api`, `opda-epc-api`, `opda-survey-shack-api` all deployed and Bruno verified |
| 2026-05-11 | `opda-competition-api` deployed with Let's Encrypt server cert, custom domain (`opda.info`), and provenance signing |
