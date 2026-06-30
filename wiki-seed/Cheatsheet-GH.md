# Cheatsheet: GitHub CLI

Paste-ready `gh` commands for the OPDA API family. Procedures with context are in
the [[Runbook]]; decisions in [[Decisions]].

> Replace placeholders (`<account-id>`, `<uuid>`, `<key>`, `<sha>`, `<run-id>`, …)
> with real values. Secrets are set per environment; never paste real secret values
> into a shared screen.

## opda-demo-bff — secrets + variables (dev environment)

```bash
gh secret set AWS_ROLE_ARN --body "arn:aws:iam::<account-id>:role/<role-name>" --env dev --repo Property-Data-Trust-Framework/opda-demo-bff
gh secret set OPDA_CLIENT_CERT --env dev --repo Property-Data-Trust-Framework/opda-demo-bff < certs/rtstransport.pem
gh secret set OPDA_CLIENT_KEY --env dev --repo Property-Data-Trust-Framework/opda-demo-bff < certs/rtstransport.key
gh secret set OPDA_SIGNING_KEY --env dev --repo Property-Data-Trust-Framework/opda-demo-bff < certs/rtssigning.key
gh secret set SMOOVE_API_KEY --body "<smoove-api-key>" --env dev --repo Property-Data-Trust-Framework/opda-demo-bff
gh secret set SPRIFT_API_KEY --body "<sprift-api-key>" --env dev --repo Property-Data-Trust-Framework/opda-demo-bff
gh variable set OPDA_API_BASE_URL --body "https://dev.api.smartpropdata.org.uk" --env dev --repo Property-Data-Trust-Framework/opda-demo-bff
gh variable set OPDA_CLIENT_ID --body "https://rp.directory.pdtf.raidiam.io/openid_relying_party/<uuid>" --env dev --repo Property-Data-Trust-Framework/opda-demo-bff
gh secret list --env dev --repo Property-Data-Trust-Framework/opda-demo-bff
gh variable list --env dev --repo Property-Data-Trust-Framework/opda-demo-bff
gh run watch --repo Property-Data-Trust-Framework/opda-demo-bff
gh run list --repo Property-Data-Trust-Framework/opda-demo-bff --limit 10
```

## Repo-scoped secrets / variables (default to dev environment)

```bash
# OS API key (opda-os-api)
gh secret set OS_API_KEY --body "<key>" --env dev --repo Property-Data-Trust-Framework/opda-os-api
gh variable set OS_API_BASE_URL --body "https://api.os.uk/" --env dev --repo Property-Data-Trust-Framework/opda-os-api

# Bypass auth toggle (escape hatch — default false; only flip during initial bootstrap)
gh variable set BYPASS_AUTH --body "false" --env dev --repo Property-Data-Trust-Framework/opda-lr-facade

# Image tags consumed by deploys (set after pushing opda-shared-services)
gh variable set AUTHORIZER_IMAGE_TAG --body "authorizer-<sha>" --env dev --repo Property-Data-Trust-Framework/opda-lr-facade
gh variable set MTLS_PROXY_IMAGE_TAG --body "mtls-<sha>" --env dev --repo Property-Data-Trust-Framework/opda-lr-facade

# Provider Raidiam OAuth client (server identity for introspection)
gh secret set OAUTH_CLIENT_ID --body "https://rp.directory.pdtf.raidiam.io/openid_relying_party/<uuid>" --env dev --repo Property-Data-Trust-Framework/opda-lr-facade
gh variable set OAUTH_ISSUER --body "https://matls-auth.directory.pdtf.raidiam.io" --env dev --repo Property-Data-Trust-Framework/opda-lr-facade

# Transport cert/key (NLB server cert + mTLS to Raidiam token endpoint)
gh secret set TRANSPORT_CERTIFICATE --env dev --repo Property-Data-Trust-Framework/opda-lr-facade < certs/rtstransport.pem
gh secret set TRANSPORT_KEY --env dev --repo Property-Data-Trust-Framework/opda-lr-facade < certs/rtstransport.key
gh secret set CA_TRUSTED_LIST --env dev --repo Property-Data-Trust-Framework/opda-lr-facade < certs/ca_trusted_list.pem

# Raidiam JWT signing key (RS256, used by authorizer to build client_assertion)
gh secret set SIGNING_KEY --env dev --repo Property-Data-Trust-Framework/opda-lr-facade < certs/rtssigning.key

# HMLR credentials (will end up in SSM via TF on next deploy)
gh secret set HMLR_USERNAME --body "<username>" --env dev --repo Property-Data-Trust-Framework/opda-lr-facade
gh secret set HMLR_PASSWORD --body "<password>" --env dev --repo Property-Data-Trust-Framework/opda-lr-facade
gh variable set HMLR_ENDPOINT --body "https://bgtest.landregistry.gov.uk/b2b/BGStubService/OfficialCopyWithSummaryV2_1WebService" --env dev --repo Property-Data-Trust-Framework/opda-lr-facade
gh secret set HMLR_CLIENT_CERT --env dev --repo Property-Data-Trust-Framework/opda-lr-facade < certs/hmlr-client.pem
gh secret set HMLR_CLIENT_KEY --env dev --repo Property-Data-Trust-Framework/opda-lr-facade < certs/hmlr-client.key
```

## Inspect / list (sanity checks)

```bash
# List secrets / variables for a repo's environment
gh secret list --env dev --repo Property-Data-Trust-Framework/opda-lr-facade
gh variable list --env dev --repo Property-Data-Trust-Framework/opda-lr-facade

# Workflow runs
gh run list --repo Property-Data-Trust-Framework/opda-os-api --limit 10
gh run watch --repo Property-Data-Trust-Framework/opda-os-api
gh run view <run-id> --repo Property-Data-Trust-Framework/opda-os-api --log
```

## One-time setup / repo creation

```bash
# Create the GitHub repo + scaffolding (run from the workspace root — acts on sibling repos)
./opda-ops/scripts/bootstrap-api.sh --new-repo-name opda-newapi --description "OPDA API for newapi"

# Provision/update the Actions environment (secrets + variables) for an existing repo
./opda-ops/scripts/setup-secrets.sh --repo Property-Data-Trust-Framework/opda-newapi --env dev

# Prepare Bruno env from AWS state (chains into apply-bruno-env.sh)
./opda-newapi/scripts/prepare-bruno-env.sh --environment dev
```

## Docs wiki + onboarding PDF pipeline (opda-ops)

```bash
git clone https://github.com/Property-Data-Trust-Framework/opda-ops.wiki.git
cp opda-ops/wiki-seed/*.md opda-ops.wiki/ && (cd opda-ops.wiki && git add . && git commit -m "Seed wiki" && git push)
gh workflow run "Onboarding PDF" --repo Property-Data-Trust-Framework/opda-ops
gh run watch --repo Property-Data-Trust-Framework/opda-ops
gh release view docs --repo Property-Data-Trust-Framework/opda-ops
gh release download docs --pattern onboarding.pdf --repo Property-Data-Trust-Framework/opda-ops
```

## Diagnose a bad demo SPA deploy — CI run forensics (opda-demo-bff)

```bash
gh run list --workflow Deploy --repo Property-Data-Trust-Framework/opda-demo-bff -L 10
gh run view <run-id> --repo Property-Data-Trust-Framework/opda-demo-bff --log > /tmp/deploy.log; grep -nE 'Build SPA|Deploy SPA|upload: dist/|create-invalidation|index.html|error|Error' /tmp/deploy.log
```
