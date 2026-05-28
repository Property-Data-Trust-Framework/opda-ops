# API Docs

Single static site that loads every OPDA API's OpenAPI spec into a Scalar reference UI. Same deploy pattern as `org-browser`: Vite build → S3 → CloudFront.

## Local development

```
npm install
npm run dev
```

Vite serves on `http://localhost:5173`. The Scalar UI loads specs from `public/specs/` — anything dropped in that directory is served at `/specs/<filename>` in dev and prod alike.

## Adding a new API to the docs

1. Drop or symlink the spec at `public/specs/opda-<api>.yaml`. (The `npm run sync-specs` script does this for the four current APIs from sibling repos under the sandbox.)
2. Add an entry to the `sources` array in `src/App.tsx`.
3. Rebuild and redeploy.

## Build

```
npm run build
```

Produces `dist/` ready to upload.

## Deploy

From sandbox root:

```
./deploy-api-docs.sh
```

First run creates the S3 bucket + CloudFront distribution; subsequent runs sync `dist/` and issue a CloudFront cache invalidation. Teardown lives in `teardown-api-docs.sh`.

## Sandbox build wrinkle

If you hit the esbuild postinstall segfault during `npm install` (same issue as `opda-ops/org-browser`), use `npm install --ignore-scripts`. The binary itself works fine after install — it's the version-check postinstall that misbehaves on the sandbox image.

## Spec ownership: CI-driven (after first deploy)

Each API's deploy pipeline is the source of truth for its `specs/<api>.yaml` in the bucket. After a successful `terraform apply`, the workflow:

1. Reads the live NLB DNS from `terraform output -raw nlb_hostname`
2. Substitutes the placeholder host in `openapi/api.yml` with the real one
3. `aws s3 cp` to `s3://opda-api-docs-<account-id>/specs/<api>.yaml`
4. `aws cloudfront create-invalidation` for `/specs/<api>.yaml`

So a normal API deploy ends with the spec auto-refreshed, no manual step. Implemented for `opda-lr-facade` today; the same shape applies to the .NET APIs once they ship `/openapi` endpoints (their workflow step will `curl` the live `/openapi/v1.json` from the deployed Lambda rather than sed-substitute a static file).

`deploy-api-docs.sh` purposely excludes `specs/*` from its sync — running it only updates the static site code. Specs only land via CI.

## Local-dev sync (optional)

`npm run sync-specs` copies the spec from each sibling repo into `public/specs/` for local-dev iteration. It also reads optional per-API host overrides from `scripts/server-urls.env` (gitignored — copy from `server-urls.env.example`) so you can mirror the CI substitution behaviour locally. Leaving an override blank keeps the spec's default placeholder.

The Go facade's spec contains AWS-specific extensions (`x-amazon-apigateway-integration`, security schemes templated with Lambda ARNs) — Scalar ignores `x-` extensions, so they're harmless even though some `${placeholder}` strings will technically be visible if a reader inspects the raw YAML.
