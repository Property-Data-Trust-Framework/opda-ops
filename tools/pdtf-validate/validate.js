#!/usr/bin/env node
/*
 * PDTF v3.5 conformance check for the OPDA APIs.
 *
 * Validates a representative default response from each API (the PDTF v3.5
 * propertyPack shape) against the real @pdtf/schemas v3 transaction schema
 * (the same ajv validator the schemas repo uses for its own tests). See
 * README.md for a full explanation.
 *
 * Run:  node validate.js
 * Needs: a checkout of the `schemas` repo with `npm install` run in it. By
 *        default we look for it as a sibling of the workspace; override with
 *        SCHEMAS_DIR=/path/to/schemas node validate.js
 */

const path = require("path");

// Load the PDTF schemas' own validator. Resolution order:
//   1. SCHEMAS_DIR env — a local (possibly WIP) checkout of the schemas repo
//   2. the @pdtf/schemas npm package — the normal case and what CI uses
//   3. a sibling ../../../schemas checkout — convenience for this workspace
function loadPdtfSchemas() {
  if (process.env.SCHEMAS_DIR)
    return require(path.join(process.env.SCHEMAS_DIR, "index.js"));
  try {
    return require("@pdtf/schemas");
  } catch {
    return require(path.resolve(__dirname, "../../../schemas/index.js"));
  }
}

let getValidator;
try {
  ({ getValidator } = loadPdtfSchemas());
} catch (err) {
  console.error(
    `\nCould not load the PDTF schemas. Fix one of:\n` +
      `  • run 'npm install' in this directory (pulls @pdtf/schemas), or\n` +
      `  • set SCHEMAS_DIR=/path/to/schemas (a checkout with 'npm install' run).\n\n` +
      `Original error:\n  ${err.message}\n`
  );
  process.exit(2);
}

const SCHEMA_ID =
  "https://trust.propdata.org.uk/schemas/v3/pdtf-transaction.json";

/*
 * Representative fragments — these mirror what each API returns by default
 * (the `data.propertyPack` part, after unwrapping the provenance envelope).
 * Keep them in step with the mappers.
 */
const SAMPLES = {
  epc: {
    energyEfficiency: {
      certificate: { currentEnergyRating: "C", certificateNumber: "0001-2200-3300-4400-5501" },
    },
  },
  councilTax: { councilTax: { councilTaxBand: "D" } },
  mra: { environmentalIssues: { coalMining: { riskIndicator: "Yes" } } },
  facade: {
    titlesToBeSold: [
      {
        registerExtract: {
          ocSummaryData: {
            officialCopyDateTime: "2026-02-05T12:00:00Z",
            editionDate: "2026-02-05",
            propertyAddress: { addressLine: { line: ["1 Example St", "Exampletown"] }, postcodeZone: { postcode: "EX4 3PL" } },
            title: {
              titleNumber: "EXC10010",
              classOfTitleCode: "10",
              commonholdIndicator: false,
              titleRegistrationDetails: { districtName: "D", administrativeArea: "A", landRegistryOfficeName: "HMLR", latestEditionDate: "2026-02-05" },
            },
            // The facade always emits all 30 indicators (non-omitempty bools),
            // so a faithful sample includes them; real values come from HMLR.
            registerEntryIndicators: Object.fromEntries(
              [
                "agreedNoticeIndicator", "bankruptcyIndicator", "cautionIndicator", "ccbiIndicator",
                "chargeeIndicator", "chargeIndicator", "chargeRelatedRestrictionIndicator", "chargeRestrictionIndicator",
                "creditorsNoticeIndicator", "deathOfProprietorIndicator", "deedOfPostponementIndicator", "discountChargeIndicator",
                "equitableChargeIndicator", "greenOutEntryIndicator", "homeRightsChangeOfAddressIndicator", "homeRightsIndicator",
                "leaseHoldTitleIndicator", "multipleChargeIndicator", "nonChargeRestrictionIndicator", "notedChargeIndicator",
                "pricePaidIndicator", "propertyDescriptionNotesIndicator", "rentChargeIndicator", "rightOfPreEmptionIndicator",
                "scheduleOfLeasesIndicator", "subChargeIndicator", "unidentifiedEntryIndicator", "unilateralNoticeBeneficiaryIndicator",
                "unilateralNoticeIndicator", "vendorsLienIndicator",
              ].map((k) => [k, false])
            ),
            proprietorship: { registeredProprietorParty: [{ privateIndividual: { name: { surnameName: "SMITH", forenamesName: "JANE" } } }] },
          },
          ocRegisterData: {
            propertyRegister: { registerEntry: [{ entryNumber: "1", entryText: ["Freehold land edged red."] }] },
            proprietorshipRegister: { registerEntry: [{ entryNumber: "1", entryText: ["PROPRIETOR: Jane Smith."] }] },
          },
        },
      },
    ],
  },
};

/*
 * One check per API. `overlays` are the PDTF source-document overlays that
 * define the detail for that section (empty = the core schema already defines
 * it). `scope` restricts which errors we care about to that API's slice of the
 * pack (a full overlay also demands OTHER sections we don't provide — that's
 * expected, not our bug).
 */
const CHECKS = [
  { api: "EPC", sample: SAMPLES.epc, overlays: [], scope: "/energyEfficiency" },
  { api: "Council Tax", sample: SAMPLES.councilTax, overlays: [], scope: "/councilTax" },
  { api: "MRA coalfield", sample: SAMPLES.mra, overlays: ["nts2023"], scope: "/coalMining" },
  { api: "HMLR facade", sample: SAMPLES.facade, overlays: ["oc1v21"], scope: "/registerExtract" },
];

const isCompleteness = (msg) => msg.includes("must have required property");

let anyStructural = false;

for (const { api, sample, overlays, scope } of CHECKS) {
  const validate = getValidator(SCHEMA_ID, overlays);
  validate({ propertyPack: sample });
  const errors = (validate.errors || [])
    .map((e) => ({ path: e.instancePath || "/", msg: e.message }))
    .filter((e) => e.path.includes(scope));

  const structural = errors.filter((e) => !isCompleteness(e.msg));
  const completeness = errors.filter((e) => isCompleteness(e.msg));

  const overlayLabel = overlays.length ? ` [overlay: ${overlays.join(", ")}]` : " [core schema]";
  if (structural.length === 0) {
    console.log(`\n✅ ${api}${overlayLabel} — structurally conformant`);
  } else {
    anyStructural = true;
    console.log(`\n❌ ${api}${overlayLabel} — ${structural.length} structural problem(s):`);
    for (const e of structural) console.log(`     ${e.path}  ${e.msg}`);
  }
  if (completeness.length) {
    console.log(`   ℹ️  ${completeness.length} completeness item(s) a full source document also needs`);
    console.log(`      (real upstream data usually supplies these; not a mapping error):`);
    for (const e of completeness.slice(0, 6)) console.log(`        ${e.path}  ${e.msg}`);
    if (completeness.length > 6) console.log(`        …and ${completeness.length - 6} more`);
  }
}

console.log(
  "\n" +
    (anyStructural
      ? "RESULT: structural problems found — a mapper is emitting a shape the schema rejects."
      : "RESULT: all fragments structurally conform to PDTF v3.5. ✅") +
    "\n"
);
process.exit(anyStructural ? 1 : 0);
