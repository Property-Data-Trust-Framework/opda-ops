# ADR-0003: Target ALB-native mTLS with Regional API Gateways

- **Status:** Proposed (target state)
- **Date recorded:** 2026-06-25
- **Builds on:** [[ADR-0002-shared-nlb-path-routing-proxy|ADR-0002]]

## Context

The shared ECS mTLS proxy ([[ADR-0002-shared-nlb-path-routing-proxy|ADR-0002]]) is a
custom layer we own and operate. AWS Application Load Balancer has supported mutual
TLS natively since late 2023. Once the custom domain is stable, the proxy becomes
removable.

## Decision

Migrate TLS termination from the ECS proxy to an **AWS ALB**:

- **Server TLS** via **ACM** (free, auto-renews — no 90-day cert concern).
- **Client cert validation** via an **S3-backed truststore** (the OPDA CA bundle,
  configured once).
- **Path-based routing** built into the ALB (replaces the SSM routing table).
- Switch the per-API API Gateways from **Private** to **Regional**.

## Consequences

- **Removed entirely:** the ECS Fargate proxy (all tasks), the NLB, the custom proxy
  routing code, per-API transport cert SSM params, and the per-repo CA bundle.
- **Per-API keys simplify** to just the Raidiam identity keys — `rtssigning`
  (`private_key_jwt`) and `dataprov` (provenance). Transport cert + CA bundle move
  to the shared ALB layer.
- **Trade-off:** Regional API Gateways are publicly resolvable (not
  VPC-endpoint-only). The private API Gateway's network isolation is exchanged for a
  simpler topology; security is maintained by **mTLS at the ALB + OAuth2 token
  introspection at the Lambda authorizer** ([[ADR-0011-security-model-mtls-oauth-introspection|ADR-0011]]).
  **Acceptable for this use case; not appropriate where network isolation is a hard
  compliance requirement.**

## Alternatives considered

- **Keep the ECS proxy** — works, but is a custom component to run and pay for, and
  duplicates capability ALB now provides natively.
- **ALB → Private API Gateway directly** — not possible; ALB cannot target a Private
  REST API Gateway, which is why the move to Regional (or Lambda target groups) is
  required.
