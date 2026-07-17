# auth-stub — sandbox OAuth issuer (ADR-0012)

Replaces the Raidiam directory for the two things the platform actually uses at
runtime: minting client-credentials tokens and RFC 7662 introspection. Source:
`opda-shared-services/cmd/authstub/` (image `authstub-<sha>` in the shared ECR repo,
built by publish.yml).

## Design in one paragraph

One Lambda behind a **private API Gateway, routed through the shared mTLS proxy**
under the `/auth` prefix — so the issuer is
`https://dev.api.smartpropdata.org.uk/auth` for every consumer (Bruno, the BFF, and
the per-API authorizers, which reach it via NAT exactly as they reached Raidiam).
Public Lambda Function URLs on this account need an extra `lambda:InvokeFunction`
grant that Terraform cannot express (console-only, lost on recreate — see
Key-Learnings), hence the estate-standard exposure pattern instead.
The proxy **exempts `/auth/` from its bearer-presence check** (these endpoints are
where tokens come from; `TOKENLESS_PATH_PREFIXES` in `cmd/mtls`, default `/auth/`).
Tokens are stateless HMAC blobs, introspection **never returns `cnf`** (authorizer
cert-binding self-disables), and client-assertion signatures are deliberately NOT
validated (sandbox-grade; hardening options: validate `private_key_jwt` against
registered JWKS, add `cnf` + mTLS, per-client TTLs).

## Deploy order (matters!)

1. Push `opda-shared-services` — publish.yml builds `authstub-<sha>` AND a fresh
   `mtls-<sha>` (the proxy gained the /auth exemption). Note both tags.
2. Apply this root:
   ```bash
   BUCKET="ops-terraform-state-$(aws sts get-caller-identity --query Account --output text)"
   terraform init -backend-config="bucket=$BUCKET" -backend-config="region=eu-west-2"
   TF_VAR_hmac_key="$(openssl rand -base64 48)" \
   TF_VAR_clients_json='{"<the BFF OPDA_CLIENT_ID relying-party URL>":{"scopes":["land-registry","transaction-status","property-pack","material-info"]},"bruno":{"scopes":["land-registry"]}}' \
   TF_VAR_authstub_image_tag="authstub-<sha>" \
     terraform apply
   ```
3. Re-apply `opda-ops/terraform/shared-proxy` with the new `mtls-<sha>` tag (picks up
   the /auth exemption) — this also force-cycles the ECS tasks, which reloads the
   routing table and picks up the new `/auth` route registered by step 2.

## Smoke test

```bash
TOKEN=$(curl -s -X POST "https://dev.api.smartpropdata.org.uk/auth/token" -d "grant_type=client_credentials&client_id=bruno&scope=land-registry" | jq -r .access_token)
curl -s -X POST "https://dev.api.smartpropdata.org.uk/auth/token/introspection" -d "token=$TOKEN" | jq .
# expect: {"active": true, "client_id": "bruno", "scope": "land-registry", ...} and NO cnf field
```

## Registry keys — match what clients SEND

Keys are the literal `client_id` form values consumers post: the BFF sends its
Raidiam relying-party URL (`gh variable get OPDA_CLIENT_ID --env dev --repo
Property-Data-Trust-Framework/opda-demo-bff`), Bruno's stub-auth env sends `bruno`.
A friendly name the client never sends ⇒ `invalid_client` ⇒ BFF 502s (learned
2026-07-16). After registry changes, force the warm Lambda to reload (see below).

## Rotation / registry changes

Both live in SSM (`/opda/auth-stub/hmac_key`, `/opda/auth-stub/clients`) and are
Terraform-managed: change the TF_VARs and re-apply. Rotating the HMAC key instantly
invalidates all outstanding tokens (clients just re-mint). The Lambda caches both at
cold start — force a refresh with
`aws lambda update-function-configuration --function-name opda-auth-stub --description "bump $(date +%s)"`
or wait for natural cold starts.
