# auth-stub — sandbox OAuth issuer (ADR-0012)

Replaces the Raidiam directory for the two things the platform actually uses at
runtime: minting client-credentials tokens and RFC 7662 introspection. Source:
`opda-shared-services/cmd/authstub/` (image `authstub-<sha>` in the shared ECR repo,
built by publish.yml).

## Design in one paragraph

One Lambda behind a public **Function URL** — the URL is the issuer. Tokens are
stateless HMAC blobs (`base64url(client_id|scope|exp).base64url(mac)`), so there is
no token store. Introspection recomputes the MAC and **never returns `cnf`**, which
makes the per-API authorizer's RFC 8705 certificate binding self-disable — zero
authorizer code changes; each API repo just points `OAUTH_ISSUER` here. Client
assertion signatures are deliberately NOT validated (sandbox-grade): registration in
the SSM client registry constrains `client_id` and scopes only. Hardening options if
this ever outlives the sandbox: validate `private_key_jwt` against registered JWKS,
add `cnf` + mTLS, per-client TTLs.

## Apply (local, like shared-vpc)

```bash
BUCKET="ops-terraform-state-$(aws sts get-caller-identity --query Account --output text)"
terraform init -backend-config="bucket=$BUCKET" -backend-config="region=eu-west-2"
TF_VAR_hmac_key="$(openssl rand -base64 48)" \
TF_VAR_clients_json='{"demo-bff":{"scopes":["land-registry","transaction-status","property-data","material-info"]},"bruno":{"scopes":["land-registry"]}}' \
TF_VAR_authstub_image_tag="authstub-<sha from publish.yml summary>" \
  terraform apply
```

Outputs: `issuer_url` (→ every repo's `OAUTH_ISSUER` GitHub variable) and
`token_endpoint` (→ BFF `OPDA_TOKEN_ENDPOINT` variable + Bruno `stub-auth` envs).

## Smoke test

```bash
ISSUER=$(terraform output -raw issuer_url)
TOKEN=$(curl -s -X POST "$ISSUER/token" -d "grant_type=client_credentials&client_id=bruno&scope=land-registry" | jq -r .access_token)
curl -s -X POST "$ISSUER/token/introspection" -d "token=$TOKEN" | jq .
# expect: {"active": true, "client_id": "bruno", "scope": "land-registry", ...} and NO cnf field
```

## Rotation / registry changes

Both live in SSM (`/opda/auth-stub/hmac_key`, `/opda/auth-stub/clients`) and are
Terraform-managed: change the TF_VARs and re-apply. Rotating the HMAC key instantly
invalidates all outstanding tokens (clients just re-mint). The Lambda caches both at
cold start — force a refresh with
`aws lambda update-function-configuration --function-name opda-auth-stub --description "bump $(date +%s)"`
or wait for natural cold starts.
