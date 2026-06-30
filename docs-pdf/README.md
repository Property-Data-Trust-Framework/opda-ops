# Docs pipeline — wiki + onboarding PDF

This directory builds the **onboarding-guide PDF** from the GitHub **wiki** and publishes it as
a GitHub **Release asset**. The whole thing is GitHub-native — **no AWS dependency** — so the
knowledge-transfer materials survive the sandbox AWS account being torn down.

- **Building it locally:** see [BUILDING.md](BUILDING.md).
- **Making the repo/wiki public:** see [../PUBLISHING.md](../PUBLISHING.md).

## Model

```
GitHub Wiki (opda-ops.wiki.git)        ← source of truth, edited in-browser
  ├─ Home, Onboarding, Runbook, Key-Learnings, Decisions (ADRs), …
  │
  │  edit Onboarding  ⇒  `gollum` event
  ▼
.github/workflows/onboarding-pdf.yml   ← runs in this repo
  clone wiki → MkDocs + with-pdf → onboarding.pdf → `docs` release asset
```

- **Living docs** = the wiki (free, GitHub-hosted, in-browser editing).
- **Generated deliverable** = the onboarding PDF, attached to the `docs` release.
- **Stable link** (put this anywhere): `https://github.com/Property-Data-Trust-Framework/opda-ops/releases/download/docs/onboarding.pdf`

## Files

| File | Purpose |
|---|---|
| `mkdocs.yml` | MkDocs config; `with-pdf` plugin produces `site/pdf/onboarding.pdf` |
| `pdf.css` | OPDA-branded print stylesheet (matches the SPA design system) |
| `BUILDING.md` | How to render the PDF locally (cross-platform) |
| `../.github/workflows/onboarding-pdf.yml` | The `gollum` / `workflow_dispatch` pipeline |
| `../wiki-seed/` | First-draft wiki pages to push into `opda-ops.wiki.git` |

## One-time setup

1. **Seed the wiki** from `../wiki-seed/` (the wiki is a separate git repo):
   ```bash
   gh repo view Property-Data-Trust-Framework/opda-ops --web   # Wiki tab → create the first page so the wiki repo exists
   git clone https://github.com/Property-Data-Trust-Framework/opda-ops.wiki.git
   cp wiki-seed/*.md opda-ops.wiki/ && cd opda-ops.wiki && git add . && git commit -m "Seed wiki" && git push
   ```
2. **Merge this scaffold to `main`** — the `gollum` trigger only works when the workflow is on
   the default branch.
3. **First build:** trigger `workflow_dispatch` once (Actions tab → "Onboarding PDF" → Run), or
   just edit the Onboarding wiki page. It creates the `docs` release and uploads the PDF.

## Selecting which wiki pages go in the PDF

The workflow copies `wiki/Onboarding.md` → `build/docs/index.md`. To add sections, copy more
pages in the "Assemble" step of the workflow **and** list them under `nav:` in `mkdocs.yml`.

## PDF backend note

`mkdocs-with-pdf` renders via **WeasyPrint**, which needs Pango/Cairo system libs (installed in
the workflow; also `fonts-dejavu-core` for glyph fallback). If you'd rather a single-document
tool with no MkDocs site, **pandoc + WeasyPrint** is a lighter alternative for a pure PDF — swap
the build step and keep everything else.
