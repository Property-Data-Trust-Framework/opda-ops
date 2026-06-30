# ADR-0007: Single shared VPC published to SSM

- **Status:** Accepted
- **Date recorded:** 2026-06-25 (migration performed 2026-04-21)

## Context

Under the per-API stack model ([[ADR-0001-per-api-self-contained-stacks|ADR-0001]])
each API provisioned its own VPC, subnets, NAT, and VPC endpoints. That duplicated
networking across every repo, multiplied cost, and made per-API IAM carry full
VPC-lifecycle permissions.

## Decision

Provision **one shared VPC** and publish its identifiers to SSM:

- VPC + subnets + NAT + 8 VPC endpoints provisioned **once** in
  `opda-ops/terraform/shared-vpc/`.
- Five SSM outputs: `/opda/shared/vpc_id`, `public_subnet_ids`,
  `private_subnet_ids`, `vpc_endpoints_security_group_id`,
  `execute_api_vpc_endpoint_id`.
- Per-API repos read these via `data "aws_ssm_parameter"` in `vpc.tf`.
- `local.name_prefix = "${var.name}-${var.environment}"` — per-API resources carry
  the environment in their name. **ECR stays at `var.name`** (shared across
  environments).
- The `-facade` suffix was removed from shared-infra modules (NLB, API GW, log
  group, IAM logging role).

## Consequences

- Per-API IAM VPC block trimmed to **SG management + describe + Lambda ENI
  lifecycle** only; pipelines no longer create/delete VPC/NAT/subnet/IGW/endpoints.
- NLB name length has headroom: `opda-uprn-validator-pr-123` = 26 chars, under the
  32-char AWS limit — relevant when adding ephemeral-environment suffixes (see
  [[Production-Readiness]]).
- **Known gap:** a single NAT Gateway is a HA risk (one AZ failure takes down all
  outbound). Tracked in [[Production-Readiness]].
- All future work should assume the post-migration shape.

## Alternatives considered

- **Per-API VPCs** (the prior state) — rejected: duplicated cost and broad IAM.
- **Terraform remote-state references** instead of SSM — SSM was chosen so consumers
  depend on a stable published contract rather than each other's state files.
