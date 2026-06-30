# OPDA Onboarding Guide

Welcome to the **Open Property Data Association (OPDA)** smart property platform. This guide gets a new
engineer from zero to productive: what the project is, how the pieces fit, how to run and deploy
things, and where to look when you're stuck.

> This guide is the source for the **downloadable onboarding PDF**, regenerated automatically
> whenever this page is edited. For day-to-day operational detail see the **[[Runbook]]** and
> **[[Key-Learnings]]** pages.

---

## 1. What this project is

A greenfield build of the OPDA property-data **platform** and its partner-API integrations,
running on AWS and gated behind the **Raidiam** trust framework. The headline deliverable is a
set of reusable, well-documented services and infrastructure that a future team can use to
stand up a **production** version of the OPDA data-sharing platform.

It is organised as a **multi-repo** estate: a Go facade, several .NET partner APIs, shared
infrastructure, and a stakeholder-facing demo (SPA + BFF).

## 2. Architecture at a glance

```
                       ┌─────────────────────────┐
   Consumer  ──mTLS──▶ │  Shared mTLS proxy (NLB) │ ──▶  Raidiam-gated APIs
   (FAPI/OAuth)        │  ECS Fargate             │
                       └─────────────────────────┘
                                  │
          ┌───────────────────────┼───────────────────────────┐
          ▼                       ▼                            ▼
  opda-lr-facade (Go)     .NET partner APIs            shared services
  Land Registry facade    epc / council-tax / mra      authorizer, signing,
  + HMLR SOAP backend     survey-shack / os / uprn      provenance, discovery
                          armalytix / smoove / …
```

- **Auth model:** Raidiam OAuth using **`private_key_jwt` (RS256)**; FAPI-style request flows;
  client **mTLS** terminated at a shared proxy. Tokens are minted against the Raidiam issuer.
- **Data provenance:** responses are **RSA-signed (RS256) over the RFC 8785 JCS-canonicalised
  payload** so consumers can verify the source.
- **Demo layer:** `opda-demo-bff` (a .NET BFF) fronts a vanilla-JS SPA (the *Property Data
  Visualiser*) that walks a property transaction through five roles against the live APIs.

## 3. Repo topology

| Repo | Language | Role |
|---|---|---|
| `opda-lr-facade` | Go | Land Registry facade + HMLR SOAP backend + authorizer Lambda |
| `opda-epc-api`, `opda-council-tax-api`, `opda-mra-api`, `opda-survey-shack-api` | .NET | Property-data partner APIs |
| `opda-os-api`, `opda-uprn-validator` | .NET | OS Places lookups + UPRN validation |
| `opda-armalytix-api`, `opda-smoove-api`, `opda-competition-api` | .NET | Source-of-funds, conveyancing events, hackathon |
| `opda-shared-services`, `opda-shared-dotnet`, `opda-shared-infra` | mixed | Shared libraries, signing/provenance, base infra |
| `opda-ops` | IaC + scripts | **You are here** — shared VPC/proxy/DNS Terraform, bootstrap scripts, Bruno, docs |
| `opda-demo-bff` | .NET + JS | Demo BFF + the Property Data Visualiser SPA |

## 4. Get set up

You'll need: **git**, the **GitHub CLI (`gh`)**, **AWS CLI v2**, **Go**, the **.NET SDK**,
**Node + npm**, **Terraform**, and **Bruno** (API client). On this project you typically:

1. **Clone the repos** under one parent directory (they reference each other by sibling path).
2. **Authenticate**: `gh auth login` and `aws sso login` / `aws configure` for the project
   account (`<AWS_ACCOUNT_ID>`, region `eu-west-2`).
3. **Read the [[Runbook]]** — it has the exact deploy, bootstrap, and verify commands.
4. **Set up Bruno** — import the collection in `opda-ops/bruno`. The `aws` environment holds
   the endpoints; your client identity and secrets (`clientId`, `clientRequestId`, `signingKey`,
   `bearerToken`, partner API keys) are Bruno `vars:secret` you set locally, never committed — so
   token requests will 401 until you populate them.

> **Heads-up (Bruno hygiene):** delete any leftover template requests before your first run —
> a shared proxy means a stray request can silently hit the wrong API. And never put `//`
> comments in a `.bru` file: Bruno will silently hide every request in that folder.

## 5. How a request actually flows

1. Client obtains a token from Raidiam via `private_key_jwt` (signs a JWT with the client
   **signing key**, RS256).
2. Client calls the API **over mTLS** (transport cert/key) through the shared proxy.
3. The **authorizer** validates the token/scopes; the API does its work.
4. The API **signs its response** (RSA signature over the JCS-canonicalised payload) so the
   consumer can prove provenance.

If you're seeing 401/403, it's almost always the token, the scope, or the mTLS cert — the
[[Key-Learnings]] page has the specific gotchas (Raidiam discovery versioning, cert reload,
clock skew, etc.).

## 6. Deploying

Each service repo has a `.github/workflows/deploy.yml` (push-to-main deploy). Shared infra
(VPC, mTLS proxy, DNS) lives in `opda-ops/terraform`. The standard loop:

```bash
# from a service repo
go build ./...           # or: dotnet build
go test ./...            # or: dotnet test
# then push — CI builds the artifact, deploys the Lambda/ECS service, publishes the OpenAPI spec
```

Full first-time bootstrap, teardown, and Raidiam org-migration procedures are in the
**[[Runbook]]**.

## 7. Local development

- Each API runs locally against its own data store (DynamoDB tables / seed files).
- A `BYPASS_AUTH` escape hatch exists for **local/dev only** to skip the Raidiam token dance —
  see the Runbook. It must never be enabled in a deployed environment.
- The demo SPA lives in `opda-demo-bff/spa` (`src/` → `dist/` via `node build.mjs`); the BFF
  proxies all upstream calls so the SPA only ever talks to `/demo-api/*`.

## 8. Conventions & gotchas (read these early)

- **UPRNs are padded to 12 digits** across all data stores — short UPRNs silently 404 otherwise.
- **CSV seed files must be LF**, not CRLF — CRLF silently breaks DynamoDB `put-item` loads.
- **API versioning is required** for Raidiam discovery — unversioned paths won't be discoverable.
- **Provenance signing** is centralised in shared services — don't hand-roll JWS per API.
- Secrets live in **GitHub Actions secrets / Bruno `vars:secret`**, never in the repo. The
  `keys/` directory is gitignored; `scripts/.env.*` (except `.env.example`) is gitignored.

## 9. Where to find things

| You want… | Look in |
|---|---|
| Exact deploy / bootstrap / teardown commands | **[[Runbook]]** |
| Why something is built the way it is; debugging gotchas | **[[Key-Learnings]]** |
| Current status / what's deployed | Project STATUS notes |
| Shared infra (VPC, proxy, DNS) | `opda-ops/terraform` |
| Bootstrap a new API repo | `opda-ops/scripts/bootstrap-api.sh` + the Runbook |
| API request examples | `opda-ops/bruno` |

## 10. Your first day, concretely

1. Read this guide end to end, then skim the [[Runbook]] and [[Key-Learnings]].
2. Get `gh` + AWS auth working against `<AWS_ACCOUNT_ID>` / `eu-west-2`.
3. Clone the repos as siblings; build one Go service and one .NET service locally.
4. Run a Bruno request end-to-end (token → mTLS call → verify signed response).
5. Make a tiny doc fix to *this* page and watch the onboarding PDF regenerate — that confirms
   your access and shows the docs pipeline in action.

---

*Maintained in the `opda-ops` wiki. Edits here automatically rebuild the onboarding PDF
([download the latest](../../releases/download/docs/onboarding.pdf)).*
