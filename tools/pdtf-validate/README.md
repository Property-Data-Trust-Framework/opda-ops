# PDTF v3.5 conformance check

A small script that checks the OPDA APIs' default responses (the PDTF v3.5
`propertyPack` shape) really do match the official **Property Data Trust
Framework** schema — not just "looks right to us", but "passes the same
validator the PDTF schemas repo uses itself".

## The jargon, in plain English

**JSON Schema** — a rulebook, itself written in JSON, that says what a valid JSON
document looks like: which fields exist, their types, allowed enum values, what's
required, how things nest. PDTF publishes its data model as JSON Schema (the
`@pdtf/schemas` package, version 3.5.0).

**ajv** ("Another JSON Validator") — the most common JavaScript library that
*reads* a JSON Schema and *checks* a document against it. You hand it a schema and
a document; it answers `true`/`false` and, when false, a list of exactly what's
wrong and where. We don't configure ajv ourselves — we borrow the schemas repo's
own pre-configured validator, so we validate against PDTF *exactly* the way PDTF
does (it knows to ignore PDTF's custom annotations like `baspiRef`, and to honour
the `discriminator`/`oneOf` branching in the schema).

**jest** — a JavaScript *test runner* (like `dotnet test` or `go test`, but for
JS). The schemas repo uses jest for its own test suite. We don't need jest here —
this is a plain one-file script you run with `node`. (If we later want this in CI,
it can become a jest test; for a manual confidence check, a script is simpler.)

**Overlay** — PDTF's core schema defines the *shapes*; "overlays" layer on the
extra rules for a specific **source document**. e.g. the `nts2023` overlay =
the "National Trading Standards" material-information rules; `oc1v21` = the "Official
Copy" (HMLR register) rules. A section like `coalMining` only gets its Yes/No enum
enforced when the relevant overlay is applied, so each check below uses the right
overlay for that API.

## Structural vs completeness — the key idea

An overlay describes a *complete* source document, so it demands lots of fields we
don't (and shouldn't) provide from a single API. The script therefore splits errors
into two buckets:

- **Structural** — a shape we got *wrong*: bad field name, wrong type, illegal enum
  value, wrong nesting. **These must be zero.** (This is what caught the MRA
  `coalMining` being nested one level too deep.)
- **Completeness** — `must have required property X`: a field a *full* document also
  needs, that this API legitimately doesn't supply on its own (or that real upstream
  data fills in). **Informational, not a bug.** (Historical example: the facade's
  `registerEntryIndicators` flags — since verified as always emitted, so they no
  longer show. You'll see completeness items whenever a sample/fragment omits a
  field a complete source document requires.)

Green = every fragment is structurally conformant. That's the bar for "our mapping
is correct".

## Run it

```
cd opda-ops/tools/pdtf-validate
node validate.js
```

Prerequisite: a checkout of the `schemas` repo with dependencies installed:

```
cd /path/to/schemas && npm install
```

By default the script looks for `schemas` as a sibling of the workspace. If it's
elsewhere:

```
SCHEMAS_DIR=/path/to/schemas node validate.js
```

Exit code is `0` when everything is structurally conformant, `1` if any structural
problem is found (so it can gate CI later).

## Reading the output

```
✅ EPC [core schema] — structurally conformant
✅ MRA coalfield [overlay: nts2023] — structurally conformant
✅ HMLR facade [overlay: oc1v21] — structurally conformant
```

If a fragment omits a field a complete source document requires, you'd also see:

```
   ℹ️  N completeness item(s) a full source document also needs …
```

- `✅ … structurally conformant` — the mapping is correct.
- `❌ … N structural problem(s)` — a mapper is emitting a shape PDTF rejects; the
  lines below give the JSON path and the reason. Fix the mapper.
- `ℹ️ … completeness item(s)` — fields a complete document also needs; expected,
  not a mapping error.

## Keeping it honest

The samples in `validate.js` are *representative* — they mirror what each API's
mapper produces. If you change a mapper, update the matching sample here. For the
strongest guarantee you would validate a **real** captured response from each
deployed API rather than a hand-written sample; the samples are the quick,
offline version.
