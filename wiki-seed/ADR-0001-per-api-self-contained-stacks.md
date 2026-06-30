# ADR-0001: Start with self-contained per-API stacks

- **Status:** Superseded by [[ADR-0002-shared-nlb-path-routing-proxy|ADR-0002]]
- **Date recorded:** 2026-06-25 (decision taken early in the project, single-service → seven APIs)

## Context

The project began as a single service (`opda-lr-facade`) and rapidly grew to seven
APIs. Each was greenfield with its own domain logic, and the priority was moving
fast without cross-service coordination overhead or shared state that one team
could break for another.

## Decision

Give every API its own self-contained stack: a dedicated NLB, ECS mTLS proxy,
private API Gateway, and Lambda. Share only the things with no per-API variation —
VPC, the `execute-api` VPC endpoint, ECR (shared-services), and the authorizer
image.

## Consequences

- **Good:** fully independent deploys, no shared state to break, zero coordination
  overhead between API teams.
- **Bad:** N identical infrastructure stacks with N different auto-generated NLB
  hostnames. Cost ~$174/month per environment at seven APIs, growing linearly with
  every new API.
- **Duplicated per API:** NLB, ECS cluster, ECS service, mTLS proxy task, SSM cert
  params, security groups, CloudWatch log group.
- The per-API NLB hostnames (`opda-*-dev-<random>.elb.eu-west-2.amazonaws.com`)
  could not carry a custom domain, and the Raidiam-issued transport cert presented
  as a server cert fails hostname validation — both of which forced the move to
  [[ADR-0002-shared-nlb-path-routing-proxy|ADR-0002]] / [[ADR-0004-public-ca-server-cert|ADR-0004]].

## Alternatives considered

- **Shared infrastructure from day one** — rejected early as premature: it would
  have imposed coordination overhead and a shared blast radius before the API
  count or domain constraints justified it. Revisited and adopted once both
  pressures materialised (see ADR-0002).
