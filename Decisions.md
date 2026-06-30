# Architecture Decision Records

This page indexes the **ADRs** for the OPDA smart property platform — the *why* behind the
build. Each ADR is a self-contained record: Context, Decision, Consequences, and
Alternatives, with a Status and a date.

> **These ADRs are retrospective.** They were written on 2026-06-25 to capture
> decisions taken earlier in the project, so each one records the *original*
> decision timeframe in its Context rather than pretending it was written at the
> time. Going forward, new decisions get an ADR when they are made.

For the operational gotchas *behind* these decisions — the things that bit us —
see **[[Key-Learnings]]**. For procedures, see **[[Runbook]]**.

## Status legend

- **Accepted** — in force.
- **Proposed** — agreed direction, not yet implemented.
- **Superseded by ADR-XXXX** — replaced; kept for the historical trail.

## Index

| # | Decision | Status |
|---|---|---|
| [0001](ADR-0001-per-api-self-contained-stacks) | Start with self-contained per-API stacks | Superseded by 0002 |
| [0002](ADR-0002-shared-nlb-path-routing-proxy) | Consolidate to a shared NLB + path-routing mTLS proxy | Accepted |
| [0003](ADR-0003-alb-native-mtls-regional-apigw) | Target ALB-native mTLS with Regional API Gateways | Proposed |
| [0004](ADR-0004-public-ca-server-cert) | Public-CA server cert; Raidiam transport cert for outbound mTLS only | Accepted |
| [0005](ADR-0005-private-key-jwt-rs256) | Raidiam client auth via `private_key_jwt` using RS256 | Accepted |
| [0006](ADR-0006-provenance-rsa-sha256-jcs) | Response provenance: RSA-SHA256 over RFC 8785 (JCS) canonical JSON | Accepted |
| [0007](ADR-0007-shared-vpc-ssm) | Single shared VPC published to SSM | Accepted |
| [0008](ADR-0008-api-versioning) | All APIs versioned (`/v1`, and `/opda/{family}/v1/{action}`) | Accepted |
| [0009](ADR-0009-container-lambda-packaging) | Container Lambdas: Go `scratch`; .NET `provided:al2023` self-contained | Accepted |
| [0010](ADR-0010-github-oidc-aws-auth) | GitHub OIDC for AWS CI auth — no long-lived credentials | Accepted |
| [0011](ADR-0011-security-model-mtls-oauth-introspection) | Security model: mTLS at the edge + OAuth2 introspection in a Lambda authorizer | Accepted |
