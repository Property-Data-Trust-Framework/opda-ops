# ADR-0002: Consolidate to a shared NLB + path-routing mTLS proxy

- **Status:** Accepted (current architecture)
- **Date recorded:** 2026-06-25 (consolidation driven by the custom-domain effort)
- **Supersedes:** [[ADR-0001-per-api-self-contained-stacks|ADR-0001]]
- **Partially superseded by (target):** [[ADR-0003-alb-native-mtls-regional-apigw|ADR-0003]]

## Context

A custom domain was in flight (pending organisational approval). This surfaced two
problems at once:

1. The per-API auto-generated hostnames ([[ADR-0001-per-api-self-contained-stacks|ADR-0001]])
   needed to converge onto one name.
2. Raidiam confirmed the server transport cert must be a public-CA cert with a
   valid hostname SAN — one hostname to certify (see [[ADR-0004-public-ca-server-cert|ADR-0004]]).

Per-API stacks also grew cost linearly.

## Decision

Consolidate to a **single shared NLB** and a **single shared ECS mTLS proxy** that
routes purely by **path prefix**, using an SSM routing table
(`{ "/uprn": apigw-url-1, "/docs": apigw-url-2, ... }`). Issue a Let's Encrypt cert
for the one shared hostname and wire Route53. The per-API private API Gateways and
Lambdas are left untouched.

## Consequences

- **Cost:** ~$44/month per environment, flat regardless of API count (~$130/month
  saving vs ADR-0001 at seven APIs).
- **New-API onboarding:** an API registers its path prefix + API Gateway URL into
  the shared SSM routing table and force-cycles the shared ECS tasks to pick up the
  route (~30s rolling refresh with `desired_count=2`).
- **Retained per API:** private API Gateway, Lambda, authorizer, signing key,
  provenance key.
- **Removed per API:** NLB, ECS cluster/service, mTLS proxy task, transport cert
  SSM params.
- **New risk:** because the proxy routes purely by path prefix, *any* Bruno request
  sharing a live prefix silently hits the wrong backend — see the "Shared proxy —
  Bruno collection hygiene" gotcha in [[Key-Learnings]].

## Alternatives considered

- **Stay on per-API stacks** — rejected: cannot carry one custom domain / one cert,
  and cost grows linearly.
- **Jump straight to ALB-native mTLS** — deferred until the domain is stable; it
  also requires moving API Gateways to Regional. Captured as the target state in
  [[ADR-0003-alb-native-mtls-regional-apigw|ADR-0003]].
