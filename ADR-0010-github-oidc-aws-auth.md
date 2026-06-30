# ADR-0010: GitHub OIDC for AWS CI auth — no long-lived credentials

- **Status:** Accepted
- **Date recorded:** 2026-06-25

## Context

CI needs to deploy to AWS. The Raidiam reference setup uses long-lived AWS
credentials (assumed). Storing static access keys in CI is a standing credential to
leak or rotate.

## Decision

GitHub Actions authenticates to AWS via **OIDC** — the workflow assumes an AWS IAM
role through the GitHub OIDC provider; **no AWS access keys are stored** anywhere.

- **One GitHub Actions role per repo**, shared across environments.
- Role policy uses `${var.name}-*` wildcards to cover env-prefixed resources.
- Per-repo IAM lives in `terraform/iam/` with its **own state file**
  (`{repo}/iam/terraform.tfstate`); `terraform destroy` on an environment does
  **not** delete the role.

## Consequences

- No stored AWS secrets — improves on the Raidiam reference (see comparison in
  [[Key-Learnings]]).
- Role-policy changes are **chicken-and-egg**: the role needs the new policy before
  CI can run under it, so role-policy changes must be applied locally first.
- The OIDC trust policy currently allows `ref:refs/heads/main` and named
  environments only. **PR-triggered teardown** (`pull_request` subject) needs an
  additional trust condition or a separate teardown role — see
  [[Production-Readiness]].

## Alternatives considered

- **Long-lived IAM user access keys in GitHub secrets** — rejected: standing
  credential, rotation burden, leak risk.
- **One shared role across all repos** — rejected in favour of per-repo roles for
  blast-radius isolation.
