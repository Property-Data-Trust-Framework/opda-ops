# ADR-0006: Response provenance — RSA-SHA256 over RFC 8785 (JCS) canonical JSON

- **Status:** Accepted
- **Date recorded:** 2026-06-25

## Context

API responses need verifiable **data provenance** so a consumer can confirm the
payload came from us and was not altered in transit. Provenance signing follows a
single canonical implementation — APIs do not hand-roll their own JWS
(see the Raidiam comparison in [[Key-Learnings]]). In practice the canonical
`ProvenanceSigner` lives in the `opda-ops` dotnet template and is copied per-repo
(there is no shared library); the Go facade has its own equivalent in
`internal/provenance/`.

## Decision

Sign each response with an **RSA PKCS#1 v1.5 / SHA-256** signature computed over the
**RFC 8785 (JSON Canonicalisation Scheme, JCS)** canonicalised payload, wrapped in a
custom `ProvenanceBlock`.

- Canonical implementation: `opda-mra-api/src/OpdaMiningRemediation/Provenance/ProvenanceSigner.cs`
  and `Jcs.cs`.
- Signing key: `dataprov.*`, per API, stored in SSM as a **SecureString**
  (`dataprov_key`).

## Consequences

- Canonicalisation is deterministic, so the signature is reproducible by any
  verifier that applies RFC 8785 before checking the RSA-SHA256 signature.
- **This is explicitly *not* JWS/ES256.** Earlier docs mis-stated provenance as
  "signed (JWS, ES256)"; there is no ES256 anywhere in the estate. This ADR is the
  source of truth — the onboarding guide was corrected to match (2026-06-24).
- The signer is constructed in `Program.cs` and **captured by closure** in the route
  handler (it does not need DI registration). A route handler that forgets to use
  the closure will silently return unsigned responses — see the packaging pitfalls
  in [[Key-Learnings]].

## Alternatives considered

- **JWS / JOSE (e.g. ES256)** — rejected: adds JOSE dependency and key-type churn for
  no benefit here; the JCS + detached-signature approach is simpler to verify and
  keeps the payload as plain JSON.
- **Per-API bespoke signing** — rejected in favour of a centralised shared
  implementation to avoid drift between services.
