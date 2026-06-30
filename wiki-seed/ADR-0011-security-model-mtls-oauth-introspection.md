# ADR-0011: Security model — mTLS at the edge + OAuth2 introspection in a Lambda authorizer

- **Status:** Accepted
- **Date recorded:** 2026-06-25

## Context

The APIs are Raidiam-gated and must enforce FAPI-style security: mutual TLS plus
OAuth2. This is the foundational security decision the rest of the architecture
(certs, proxy, authorizer) serves.

## Decision

Enforce security in two layers:

1. **Client mTLS at the edge** (the shared ECS proxy today; the ALB under
   [[ADR-0003-alb-native-mtls-regional-apigw|ADR-0003]]). The proxy uses
   **`tls.VerifyClientCertIfGiven`** — it *always requests* a client cert and
   verifies it if present, which lets NLB health checkers (which present no cert)
   through while still enforcing mTLS for real traffic. (An earlier
   `RequireAndVerifyClientCert` killed health checks; an even earlier SNI-gated
   request meant no cert was requested at all on the raw NLB hostname.)
2. **OAuth2 token introspection at a Lambda authorizer.** The authorizer introspects
   the bearer token against Raidiam (cert-bound, via
   [[ADR-0005-private-key-jwt-rs256|ADR-0005]]) and surfaces the token scopes into
   the request context for the service Lambda's scope filter.

The API Gateway resource policy is additionally conditioned on the VPC endpoint
source (`aws:SourceVpce`) while gateways are Private (Phase 1/2).

## Consequences

- Defense in depth: transport-layer client authentication **and** token-level
  authorisation; neither alone is sufficient to call an endpoint.
- Health-check compatibility is preserved by `VerifyClientCertIfGiven`.
- A **`BYPASS_AUTH` escape hatch** exists for very early bootstrap (before Raidiam
  certs exist). It defaults to `false` and must never be enabled in a deployed
  environment — when `true`, the authorizer never runs, so scope-protected endpoints
  401 (no claims). Documented in [[Runbook]] / [[Key-Learnings]].
- The authorizer Lambda permission is currently account+region-scoped to all API
  Gateways (a deliberate circular-dependency workaround). Tightening to the specific
  API Gateway execution ARN is tracked in [[Production-Readiness]].

## Alternatives considered

- **mTLS only** — rejected: identifies the transport client but carries no scoped
  authorisation.
- **OAuth2 only** (no mTLS) — rejected: Raidiam requires cert-bound tokens; the
  transport identity is part of the trust model.
- **JWT validation in-Lambda instead of introspection** — introspection is used
  because Raidiam issues cert-bound, introspectable tokens and it centralises the
  trust check in the authorizer.
