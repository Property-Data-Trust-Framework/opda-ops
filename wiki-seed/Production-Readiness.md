# Production Readiness

Gaps that are **not** blockers for sandbox/dev but **must close before go-live**, plus
the pre-conditions for turning on ephemeral environments. Use this as the go-live
checklist. Decisions are in [[Decisions]]; the gotchas behind them are in
[[Key-Learnings]].

## Equal concerns (also unsolved in the Raidiam reference — not differentiators)

These exist in both setups. Flagging them isn't an indictment of our build, but they
still need addressing before production.

| Concern | Detail |
|---|---|
| **Single NAT Gateway** | One AZ failure takes down all outbound (ECS image pulls, HMLR calls). Need one NAT per AZ for HA. Relates to [ADR-0007](ADR-0007-shared-vpc-ssm). |
| **ECS `desired_count = 1`** | A single mTLS proxy task = full outage until ECS reschedules. |
| **API Gateway throttling** | No usage plans / method-level rate limits. A misbehaving client can exhaust Lambda concurrency. |
| **WAF** | No layer-7 protection in front of the NLB or API Gateway. |
| **CloudWatch alarms** | No alerting on errors / latency / throttles for any service. |

## Where the Raidiam reference is ahead (genuine architectural gaps)

In rough priority order:

1. **Lambda aliases** — the biggest gap. Raidiam deploys both Lambdas with a published
   version + alias and scopes the API GW permission to the alias ARN, enabling
   weighted traffic shifting (canary), instant rollback by shifting alias weight, and
   version pinning instead of `$LATEST`. Our every-deploy-to-`$LATEST` model is
   all-or-nothing; rollback means re-running CI with a previous image tag. Medium
   effort: `publish = true`, `aws_lambda_alias`, alias-scoped permission, pipeline
   weight-shift.
2. **Reserved concurrency on the authorizer** — Raidiam explicitly sets 12. The module
   variable `reserved_concurrent_executions` exists but `opda-lr-facade/terraform/authorizer.tf`
   never passes it, so it falls through to `-1` (unreserved). Single-line fix; prevents
   runaway scaling under spikes and guarantees capacity.
3. **Tighten the authorizer Lambda permission** — currently account+region-scoped to
   all API GWs (`arn:aws:execute-api:eu-west-2:<account>:*`), a deliberate workaround
   for the circular dep (authorizer must exist before the API GW). Tighten to the
   specific API GW execution ARN once stable, or break the circular dep with a
   two-phase apply / `depends_on`. See [[ADR-0011-security-model-mtls-oauth-introspection|ADR-0011]].
4. **Missing `ignore_changes = [value]` on HMLR SSM resources** —
   `opda-lr-facade/terraform/ssm.tf` has no lifecycle block on the HMLR cert/key SSM
   resources, so an out-of-band rotation gets clobbered by the next `terraform apply`.
   The `os_api_key` resource in `opda-os-api` already has it. Single-line addition.

> Closed since older docs were written (verified 2026-04-29): HMLR username/password
> sourcing (config fetches from SSM at runtime, populated from `TF_VAR_hmlr_*`); log
> retention (90d module default, matching Raidiam).

## Housekeeping

| Item | Fix |
|---|---|
| DevSecOps hygiene (none configured) | Dependabot, golangci-lint CI, Trivy image scanning, tflint. |

Closed since first drafted: the compiled `opda-lr-facade` binary previously committed at the repo root is gone — untracked, gitignored (`opda-lr-facade/.gitignore`), and absent from the (squashed) history.

## Pre-conditions for ephemeral environments (deferred)

The architecture is **kept compatible** with ephemeral environments (NLB name length
checked, ECR sharing confirmed — see [[ADR-0007-shared-vpc-ssm|ADR-0007]]), but the
following must close before turning them on:

| Item | Detail |
|---|---|
| **IAM OIDC trust conditions** | Trust policy currently allows `ref:refs/heads/main` and named environments only. PR-triggered teardown runs under a `pull_request` subject — needs an additional condition or a separate teardown role. See [ADR-0010](ADR-0010-github-oidc-aws-auth). |
| **Secrets strategy** | GitHub environment-scoped secrets don't scale per-PR. Move to SSM-first for certs (already in SSM after first deploy; pipeline reads from SSM rather than reloading from GitHub secrets). |
| **Automated teardown workflow** | On PR close: `terraform destroy` → delete S3 state file → optionally delete the GitHub environment. State cleanup is critical — a leftover state file confuses Terraform on the next redeploy. |
| **Post-teardown verification** | Lambda ENIs release asynchronously (15–20 min) and log groups survive failed destroys — see the AWS quirks in [[Key-Learnings]]. |
