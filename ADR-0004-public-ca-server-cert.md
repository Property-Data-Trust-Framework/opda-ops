# ADR-0004: Public-CA server cert; Raidiam transport cert for outbound mTLS only

- **Status:** Accepted
- **Date recorded:** 2026-06-25

## Context

Raidiam confirmed that **callers validate the server cert hostname** against the DNS
name of the endpoint (SANs and wildcards accepted). The Raidiam-issued transport
cert has a **UUID CN and no hostname SANs** (its CN is a participant identifier), so
presenting it as a server cert causes TLS hostname-validation failures for any
standard client.

There are several distinct cert/key pairs whose purposes are easy to confuse:

| Pair | Purpose |
|---|---|
| `tls.*` / `server_tls_*` | Inbound server TLS — the cert the proxy presents to clients |
| `rtstransport.*` / `transport_*` | Outbound mTLS — our Raidiam participant identity when calling token/introspection |
| `rtssigning.*` | `private_key_jwt` signing (see [ADR-0005](ADR-0005-private-key-jwt-rs256)) |
| `dataprov.*` | Response provenance (see [ADR-0006](ADR-0006-provenance-rsa-sha256-jcs)) |

ACM certs are **non-exportable**, so they cannot be loaded by the ECS proxy (which
reads cert+key from SSM at startup) — ACM is only usable via AWS-managed TLS
termination (ALB/NLB/CloudFront).

## Decision

Use a cert from a **publicly-trusted CA** for inbound server TLS, and reserve the
Raidiam `rtstransport.*` cert **exclusively** for outbound Raidiam mTLS:

- **Now (ECS proxy):** **Let's Encrypt** — free, exportable private key, DNS-01
  challenge via a Route53 TXT record (no HTTP server, works before deploy). Stored
  in SSM / GitHub secrets exactly like today's transport cert; zero proxy/Terraform
  changes.
- **Later (ALB):** **ACM** (free, auto-renews) once on [[ADR-0003-alb-native-mtls-regional-apigw|ADR-0003]].
- Server and transport certs use **separate SSM params** (`server_tls_*` vs
  `transport_*`); the proxy uses `server_tls_*` for inbound when set, the authorizer
  always reads `transport_*` for outbound.

## Consequences

- No more hostname-validation failures on externally-reachable endpoints.
- Let's Encrypt certs are 90-day; renewal automation is unnecessary if the sandbox
  window is ≤90 days from issuance.
- The Route53 hosted zone **must be public** — Let's Encrypt validation servers are
  on the internet and cannot reach a private zone, and consumers need public DNS.
- `transport_key` is stored as an SSM **SecureString** (tighter than the Raidiam
  reference, which uses a plain String — see the comparison in [[Key-Learnings]]).

## Alternatives considered

- **Use the Raidiam transport cert as the server cert** — rejected: UUID CN, no
  hostname SANs, fails standard TLS validation.
- **ACM directly on the ECS proxy** — not possible (non-exportable private key).
