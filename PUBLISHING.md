# Publishing `opda-ops` (and its wiki)

Checklist and record for making this repo — and the GitHub wiki it seeds — public.
The wiki is GitHub-hosted and survives the sandbox AWS account being torn down; that
durability is the whole point, so the bar for "no secrets, no surprises" is high.

## Estate-wide pre-publication scan (2026-06-25)

Full scan across all 18 repos + the wiki (6 review agents + deterministic grep). **No
AWS access keys, no committed private keys/certs, and no account-ID leaks in any
*tracked* file — except the one noted below.** Decisions taken: canonical GitHub org is
**`Property-Data-Trust-Framework`** (migration complete); the real sandbox Raidiam
client_id `70e31a1a-…` is a **public OAuth identifier and is kept as-is** by decision;
Survey Shack sample PDFs **replaced with synthetic** reports.

**Fixed in the working tree (commit per repo — git is the user's):**
- **`opda-ops` + wiki:** org rewrite `ts-opda → Property-Data-Trust-Framework`; email PII
  removed from Key-Learnings; doc-accuracy corrections (versioning table/endpoints now
  show the live `/v1` paths incl. `/v1/epc/{uprn}`; `iat` added to the documented JWT;
  `import-coalfields.sh` positional-args fix; armalytix+smoove added to repo topology);
  dangling internal-file refs removed (STATUS/TODO/etc. → wiki links); CLI run-location
  normalised (per-repo commands from repo root; orchestration scripts from workspace root).
- **`opda-competition-api`:** org rename across 7 files (`.gitmodules`, `teardown.sh`, 3
  module sources, `iam/terraform.tfvars`, `iam/variables.tf`). Account-ID already removed
  in working tree (needs commit). **README.md is untracked — `git add` it.**
- **`opda-mra-api`:** deleted `bruno.zip` (stage the deletion); README dir names fixed
  (`OpdaMiningRemediation`).
- **`opda-os-api`:** README dir names fixed (`OpdaOrdnanceSurveyApi`).
- **`opda-demo-bff`:** `ARMALYTIX_CLIENT_REQUEST_ID` externalised to a TF variable
  (default unchanged).
- **`opda-survey-shack-api`:** `files/*.pdf` replaced with synthetic placeholder reports
  (no real addresses/UPRNs).
- **`opda-lr-facade`:** `deploy.yml` HMLR insecure flag annotated sandbox-only;
  `RAIDIAM_BASELINE.md` stale `raidiam/` submodule claim reworded; internal `progress/`
  pointer dropped from `iam/terraform.tfvars`.
- **`trust-framework`:** `node_modules/` added to `.gitignore` (run `git rm -r --cached
  node_modules` to untrack).

**Remaining user / git actions before going public:**
- [ ] Commit all of the above per repo.
- [ ] `opda-competition-api`: commit the account-ID removal **and** `git add README.md`.
- [ ] `opda-mra-api`: stage the `bruno.zip` deletion.
- [ ] `trust-framework`: `git rm -r --cached node_modules` (see `git_cheatsheet.txt`).
- [ ] `lr-sandbox/aws_cheatsheet.txt` (scratch, not a repo) still has the literal account
      id — only the wiki copy is scrubbed.

**Accepted / low (no action, recorded):** real Raidiam client_id kept (public identifier);
partner staging base URLs kept (hostnames, not secrets); `terraform/iam/*.tf`+`vpc.tf`
comments naming the internal `opda-ops` repo; `normalise-certs.sh` referencing a
non-published `setup-github-env.sh`; `opda-shared-dotnet` is an empty repo;
`trust-framework/CLAUDE.md` is tracked.

## Pre-publish checklist

- [ ] **Account ID scrubbed** — no literal AWS account IDs in tracked files or the
      wiki. Use `<AWS_ACCOUNT_ID>`. (The cheatsheets in `wiki-seed/Cheatsheet-*.md`
      are already placeholdered.)
- [ ] **No private keys / tokens** — `keys/` is gitignored and never committed; no
      `BEGIN … PRIVATE KEY`, `client_secret`, `AKIA…`, or GitHub/Slack tokens in
      tracked files or history.
- [ ] **`.env` files** — only `.env.example` is tracked; real `.env.*` are gitignored
      and untracked (`git rm --cached scripts/.env.dev` if still tracked — see
      `wiki-seed/Cheatsheet-Git.md`).
- [ ] **Bruno env** — org-identifying values (`clientId`, `clientRequestId`) and
      tokens are `vars:secret`, not committed.
- [ ] **Partner base URLs** — decide whether the partner sandbox/staging hostnames
      (`spriftBaseUrl`, `vmcBaseUrl`, `pdiBaseUrl`, `smooveDirectBaseUrl`) should be
      scrubbed or `{{var}}`'d; they're hostnames, not credentials, but reveal partner
      integrations.
- [ ] **`BYPASS_AUTH`** — documented and marked dev-only (conscious decision to keep).

## Public-repo suitability scan (recorded 2026-06-22; items closed 2026-06-24)

Scan of tracked content + git history before making `opda-ops` / its wiki public.

**Clean:**
- `keys/` (signing + transport private keys) — gitignored, never committed to history.
- No AWS access keys, `BEGIN … PRIVATE KEY` blocks, `client_secret`, or GitHub/Slack
  tokens in tracked files.
- `scripts/.env.dev` — tracked, but all populated values are the literal `PLACEHOLDER`.
- Bruno `signingKey` / `bearerToken` — declared `vars:secret`, values not committed.

**Addressed / to address before public:**
- AWS account ID in `RUNBOOK.md` → **templated to `<AWS_ACCOUNT_ID>`** in the wiki
  copy (`wiki-seed/Runbook.md`). Keep it placeholdered in the wiki. The
  `wiki-seed/Cheatsheet-AWS.md` copy is likewise placeholdered (the original
  `lr-sandbox/aws_cheatsheet.txt` still carries the literal value — scrub if that
  file is ever published).
- `bruno/environments/aws.bru` — **DONE (2026-06-24):** `clientId` and
  `clientRequestId` moved into the `vars:secret` block (set locally in Bruno, no
  longer committed). `subscriptionId` is an all-zeros placeholder; remaining `vars`
  are public test data (UPRN/title/query) and public endpoint URLs. **Judgment call:**
  partner sandbox/staging base URLs (`spriftBaseUrl`, `vmcBaseUrl`, `pdiBaseUrl`,
  `smooveDirectBaseUrl`) are hostnames, not credentials, but reveal partner
  integrations — scrub or `{{var}}` them if that matters at publish time.
- `BYPASS_AUTH` documented in the Runbook — kept, marked dev-only. Conscious decision
  to publish.
- `scripts/.env.dev` — **DONE (2026-06-24):** `.env.example` already exists as the
  committed template; `.env.dev` is all-`PLACEHOLDER` and `.gitignore` already covers
  `scripts/.env.*` (with `!.env.example`). It is still *tracked* from before that
  rule, so untrack it: `git rm --cached scripts/.env.dev` (file stays on disk).

**Not a finding:** `200001858581` is a UPRN (public property id), not an account id.
