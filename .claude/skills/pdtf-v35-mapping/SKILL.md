---
name: PDTF v3.5 mapping
description: Add or verify a PDTF v3.5 schema mapping for an OPDA API. Use when mapping an OPDA API's response onto the PDTF propertyPack shape (the default response shape of all OPDA APIs), adding a new API/field to the property pack, or checking that an API's output conforms to the @pdtf/schemas v3 schema.
when_to_use: Triggered by PDTF/property-pack/propertyPack mapping work, conformance checking against @pdtf/schemas, or wiring a new OPDA API section into the transaction pack.
---

# Mapping an OPDA API to PDTF v3.5

The OPDA APIs return the PDTF v3.5 `propertyPack` shape as their **default (and
only) response**: each API emits a `propertyPack` fragment that deep-merges into
a full transaction pack (the BFF's `/demo-api/pack/` does the merging). The
legacy flat shapes were removed in July 2026 — a deliberate breaking change so
consumers of the pre-PDTF shapes surface loudly. This skill is the repeatable
procedure for adding or verifying a mapping. Follow it in order.

## 0. Where the schema lives (the source of truth)

- Canonical: the **`schemas/` repo** = `@pdtf/schemas` **v3.5.0**.
- Shapes: `schemas/src/schemas/v3/combined.json`, nested under `propertyPack`.
- **Overlays** (`schemas/src/schemas/v3/overlays/*.json`) add the rules for a
  specific *source document* — e.g. `nts2023` (material info), `oc1v21` (HMLR
  Official Copy). Detail for some sections (enums, required) is only enforced by
  the relevant overlay, **not** the permissive core schema.

## 1. Find the target path — VERIFY, never assume

`grep -nE "\"<sectionName>\": \{" schemas/src/schemas/v3/combined.json`

⚠️ **The #1 mistake:** assuming nesting from nearby line numbers. Confirm the
*actual parent* by checking indentation. Example that bit us: `coalMining` is a
**direct child of `environmentalIssues`** (sibling of flooding/radon/
groundStability), NOT under `groundStability`. The core schema is permissive and
will silently accept a wrong path — only the overlay validator catches it. List a
section's real direct children with:

`awk 'NR>=<start> && NR<=<end>' combined.json | grep -E "^            \"[a-zA-Z]+\": \{"`

Record the confirmed path (e.g. `propertyPack.energyEfficiency.certificate`).

## 2. Write the mapper (the pack fragment IS the response)

- Each API gets a `Pdtf/PdtfV35Mapper` (.NET) or `internal/pdtf` (Go) that returns
  a **`propertyPack` fragment** rooted at the confirmed path. Build nested
  dictionaries/maps with **verbatim JSON keys** (avoid camelCase serializer
  surprises like `posttown`).
- Endpoint: the handler maps the source data and returns the fragment directly —
  there is no schema query param and no flat branch. Provenance signing wraps the
  fragment (`{ data: { propertyPack }, provenance }`).
- **Field renames**: match the schema exactly (e.g. `currentEnergyEfficiencyBand`
  → `currentEnergyRating`).
- **Enums**: only emit values in the schema's enum. If a source value has no
  equivalent (e.g. council tax `UNKNOWN`, coalfield `UNKNOWN`), **omit the field**
  rather than invent one — the base object rarely requires it.
- **Recasing (HMLR facade)**: HMLR sends PascalCase; PDTF wants camelCase. Use the
  acronym-aware rule: lower a single leading cap (`TitleNumber`→`titleNumber`), and
  for a leading acronym keep its last letter as the next word's start
  (`OCSummaryData`→`ocSummaryData`, `CCBIEntry`→`ccbiEntry`). A naive
  lowercase-first-letter is WRONG.

## 3. Update everything that mirrors the shape

- **Unit/integration tests** — assert the nested path + renames + omit-on-unknown
  on the default (no-param) endpoint. (Note: unit tests assert *our* assumption —
  they will NOT catch a wrong path. Step 4 does.)
- **Bruno** — update the API's request in the repo collection AND the
  `opda-ops/bruno` mirror to assert the nested propertyPack shape.
  **Never use `//` comments in .bru files** — Bruno silently hides the whole folder.
- **BFF assembler** — if the section should appear in the merged `/demo-api/pack/`,
  update `opda-demo-bff` `PdtfPackAssembler` + `PdtfPackAssemblerTests` samples.
  The assembler output is `{ propertyPack, provenance: { perSourceKey } }` — the
  merged pack is not re-signed; per-source provenance is surfaced instead.
- **SPA** — the demo SPA reads `pack.propertyPack.*` and `pack.provenance.<key>`
  (`opda-demo-bff/spa/src/{app.js,data.js}`); update reads + bump `const VERSION`.
- **OpenAPI + README** — each repo's `openapi/api.yml` documents the propertyPack
  `data` schema; keep it in step.
- **Wiki** — update the per-API row in the `PDTF-Compliance` page.

## 4. Validate against the real schema (this is the safety net)

Run the conformance tool — it reuses the schemas repo's own ajv validator:

```bash
cd opda-ops/tools/pdtf-validate && npm ci && node validate.js
```

Add/adjust the representative sample + its check in `validate.js` for the new
section, choosing the right overlay (core for EPC/council tax; `nts2023` for
material-info sections; `oc1v21` for register data). Read results as:

- **Structural error** (wrong field name/type/enum/nesting) → **must be zero**. Fix
  the mapper. This is what catches path bugs the permissive core schema hides.
- **Completeness item** (`must have required property X`) → informational; a *full*
  source document also needs it, but a single API legitimately may not supply it
  (or real upstream data fills it in). Not a bug.

Full explanation of ajv / overlays / structural-vs-completeness:
`opda-ops/tools/pdtf-validate/README.md`.

## 5. Know what is NOT mappable

- **Transaction model**: PDTF is transaction/participant-centric; our APIs are
  UPRN lookups. The APIs emit `propertyPack` *fragments*, not the full
  participant/transaction envelope. That gap is stakeholder-gated.
- **Signing**: PDTF Verified Claims want Ed25519 Linked-Data proofs; our provenance
  is RS256/JCS.
- **Source of funds / AML (Armalytix)**: PDTF v3.5 has **no** source-of-funds model;
  the only AML slot is a thin `participants[].verification.antiMoneyLaundering`
  verdict. Do NOT force a lossy mapping — the intended home is a future
  `FundsVerificationCredential` (W3C VC) not yet defined in the trust-framework.

## Transitional note (until all four APIs are redeployed)

The BFF still appends `?schema=pdtf-v3.5` to its downstream calls so it works
against API deployments that predate the PDTF-default flip (the param is a no-op
after). Remove it from `opda-demo-bff` `Program.cs` once EPC, council-tax,
coalfield AND the LR facade are all redeployed.

## Reference

- Design + full history: `progress/2026-06-30-pdtf-v35-additive-views.md` (the
  original additive rollout) and `progress/2026-07-05-*` (the default flip)
- Per-API status: `opda-ops` wiki `PDTF-Compliance` page
- Validator + noob guide: `opda-ops/tools/pdtf-validate/README.md`
