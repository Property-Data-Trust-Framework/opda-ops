# OPDA Ops Wiki

Living documentation for the **Open Property Data Association** smart property platform. This wiki is the
**source of truth** — edit pages in the browser and changes are live immediately.

## Pages

- **[[Onboarding]]** — start here if you're new. Also published as a
  [downloadable PDF](../../releases/download/docs/onboarding.pdf) (auto-generated on every edit).
- **[[Runbook]]** — exact operational commands: deploy, bootstrap, verify, rotate, teardown.
- **[[Key-Learnings]]** — the hard-won gotchas: the things that bit us, by area.
- **[[Decisions]]** — Architecture Decision Records (ADRs): *why* the build is shaped this way.
- **[[Production-Readiness]]** — go-live gap register + ephemeral-environment pre-conditions.

**Cheatsheets** — paste-ready commands: [[Cheatsheet-AWS|AWS CLI]] ·
[[Cheatsheet-GH|GitHub CLI]] · [[Cheatsheet-Git|Git]] · [[Cheatsheet-Terraform|Terraform]]

## How the docs work

- This wiki is hosted by GitHub — **no AWS dependency**, so it outlives the sandbox account.
- Editing the **Onboarding** page triggers a GitHub Action (`gollum` event) in the `opda-ops`
  repo that rebuilds the onboarding PDF and republishes it as the `docs` release asset.
- Stable PDF link: `https://github.com/Property-Data-Trust-Framework/opda-ops/releases/download/docs/onboarding.pdf`

> **Note on contents:** keep secrets out of the wiki. Account IDs and credentials should be
> referenced as placeholders (`<AWS_ACCOUNT_ID>`), not literal values — this repo/wiki may be
> public.
