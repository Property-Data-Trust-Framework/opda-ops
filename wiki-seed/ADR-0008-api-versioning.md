# ADR-0008: All APIs versioned (`/v1`, and `/opda/{family}/v1/{action}`)

- **Status:** Accepted
- **Date recorded:** 2026-06-25

## Context

Raidiam's portal generates discovery endpoint URLs from a baseUrl + version + a
predefined path template per API family. Unversioned paths are not discoverable, so
**all APIs must be versioned**. The shared proxy ([[ADR-0002-shared-nlb-path-routing-proxy|ADR-0002]])
routes purely by first-path-segment prefix, so versioned paths must stay unambiguous
across APIs.

## Decision

- **.NET APIs** use a plain `/v1/` prefix (e.g. `/v1/uprn/validate`, `/v1/coalfield`,
  `/v1/places/find`).
- **The Go facade** uses the full `/opda/{family}/v1/{action}` pattern
  (e.g. `/opda/official-copies/v1/register-extract`).
- These are distinct first-path-segments, so shared-proxy routing remains
  unambiguous.
- **`/health` endpoints stay unversioned.**

## Consequences

- Applying versioning to an API touches: the `Program.cs` endpoint path, the
  `openapi/api.yml` path, the API Gateway (redeploys on next push), the Bruno
  `baseUrl` path, and the shared-proxy routing-table prefix.
- Some APIs already match their Raidiam-generated path; others (council-tax, epc,
  survey-shack) are pending portal pattern confirmation. The mapping table lives in
  [[Key-Learnings]].

## Alternatives considered

- **Unversioned paths** — rejected: not discoverable via the Raidiam portal.
- **A single uniform pattern for every API** — the facade's path family is dictated
  by its Raidiam "government-data" resource template, so a `/v1`-only convention
  could not cover it; the two-pattern rule keeps each consistent with its portal
  registration while remaining routable.
