# PDTF v3.5 Compliance

How the OPDA APIs map onto the **Property Data Trust Framework** schema (`@pdtf/schemas`
**v3.5.0**; canonical shapes in `schemas/src/schemas/v3/combined.json`, nested under a
transaction-centric `propertyPack`).

## Approach: PDTF v3.5 is the default response

Since July 2026, every OPDA API returns its PDTF v3.5 `propertyPack` fragment as the **default
(and only) response shape**. The legacy flat shapes were **removed entirely** — a deliberate
breaking change agreed with stakeholders: any system still consuming the pre-PDTF first-pass
shapes fails loudly and must migrate, rather than lingering silently on a deprecated contract.
The provenance envelope (RS256/JCS) wraps each fragment as before.

The BFF's `/demo-api/pack/{uprn}` deep-merges the four fragments into one pack and surfaces each
source's provenance block: `{ propertyPack, provenance: { epc, councilTax, coalfield,
titleRegister } }`. The merged pack itself is not re-signed (the BFF is an aggregator, not a
signer). The demo SPA reads this shape (v1.9+).

*Rollout history:* the mappings originally shipped as an additive opt-in view behind
`?schema=pdtf-v3.5` (June 2026), then were promoted to the default. Transitionally the BFF still
sends `?schema=pdtf-v3.5` downstream so it works against pre-flip API deployments (a no-op after);
remove once all four APIs are redeployed.

## Per-API status

| API | v3.5 target path | Status | Notes |
|---|---|---|---|
| EPC | `propertyPack.energyEfficiency.certificate` | ✅ default | Field rename `currentEnergyEfficiencyBand`→`currentEnergyRating`; ~12 of ~80 target fields populated. |
| Council Tax | `propertyPack.councilTax` | ✅ default | `UNKNOWN` band omitted (no v3.5 enum for it — distinct from `Not banded`). |
| MRA coalfield | `propertyPack.environmentalIssues.coalMining` | ⚠️ partial, default | `ON/OFF_COALFIELD`→`riskIndicator: Yes/No`. **Data-blocked**: source has no `actionAlertRating`/`summary`/`riskSubcategories`. |
| HMLR facade | `propertyPack.titlesToBeSold[].registerExtract.{ocSummaryData,ocRegisterData}` | ✅ default | Modelled by the `oc1` overlay. Raw HMLR Official Copy recased PascalCase→camelCase + wrapped. All 30 `registerEntryIndicators` emitted. |
| Armalytix (SoF) | *(none)* | ❌ not mappable | See below. |

## Armalytix / source-of-funds gap

PDTF v3.5 has **no source-of-funds data model**. The only AML element is a thin per-participant
verdict: `participants[].verification.antiMoneyLaundering = { result: pass|fail|consider,
reports:[{reportName, result, details}] }` (sibling to `verification.identity`). Our Armalytix
report (proof-of-funds verdict, accounts, income/outgoings, declared source, mortgage, flags) is
far richer and would suffer ~95% information loss if collapsed into that slot — and AML ≠ source of
funds. The intended home is a future **`FundsVerificationCredential`** (W3C Verifiable Credential),
which the trust-framework has **not yet defined**. Recommendation: keep the native shape and wait
for that credential type rather than force a lossy AML mapping. Armalytix is therefore excluded
from the merged BFF pack and keeps its standalone endpoint.

## Conformance validation

The outputs are validated against the schemas repo's own ajv validator by
`opda-ops/tools/pdtf-validate` (run locally with `npm ci && node validate.js`; also runs in CI via
`.github/workflows/pdtf-validate.yml` on PRs, pushes and a weekly upstream-drift check). All four
APIs validate with **zero structural errors** — EPC/Council Tax against the core schema, MRA against
the `nts2023` overlay, and the facade against `oc1v21` with zero completeness gaps. This tool caught
a real nesting bug (`coalMining` mis-nested under `groundStability`) that unit tests could not.

## Known blockers (deferred, stakeholder-gated)

- **Transaction model** — PDTF is transaction-centric (`participants`, `propertyPack` per
  transaction); our APIs are UPRN-keyed lookups. The APIs emit `propertyPack` fragments but do
  not model the full transaction/participant envelope.
- **Signing** — PDTF Verified Claims expect Ed25519 Linked-Data proofs; our provenance is RS256/JCS.
