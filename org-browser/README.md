# Org Browser

Tiny static site that lists participants in the OPDA directory and lets you filter by `ApiFamilyType`.

Data source: `https://data.directory.pdtf.raidiam.io/participants` — public, CORS-open, served from S3+CloudFront. No proxy needed.

## Local development

```
npm install
npm run dev
```

Vite serves on `http://localhost:5173` with HMR. The page fetches the live directory on each load — there is no build-time data baked in.

## Build a static artifact

```
npm run build
```

Output lands in `dist/` — plain HTML/CSS/JS, ready to upload to any static host.

## Deploy

Run `deploy-org-browser.sh` from the sandbox root. It builds the site, creates the S3 bucket and CloudFront distribution if they don't exist, syncs the build output, and invalidates the cache. Idempotent — safe to re-run.

```bash
./deploy-org-browser.sh
```

## Notes on the data shape

`ApiFamilyType` is **nested** inside `AuthorisationServers[].ApiResources[]`, not at the org root. The filter "show orgs of family X" means "show orgs that have any ApiResource of that family". See `src/api.ts` for the helpers.

Current dataset is small (~7 orgs) and the only family in the wild as of writing is `register-extract`, but the dropdown derives from live data so new families will show up automatically.
