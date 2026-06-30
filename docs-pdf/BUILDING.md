# Building the onboarding PDF locally

How to render the onboarding PDF on your own machine — the same output as the
`onboarding-pdf.yml` workflow, but built from `../wiki-seed/` (so no wiki/git needed).
For *what* the pipeline is and how it publishes, see [README.md](README.md).

Set two anchors first, then run **Setup** once and **Build** whenever you edit:

- `S` = path to the `opda-ops` repo
- `B` = scratch build dir

Output (all platforms): `<B>/build/site/pdf/onboarding.pdf`

> **Windows note:** WeasyPrint needs the GTK3 runtime, which Chocolatey doesn't bundle.
> The simplest route is MSYS2 — see the Windows setup step below.

---

## 1. Setup (run once) — system libs + fonts + uv

WeasyPrint needs Pango/Cairo; `fonts-dejavu` provides the glyph fallback for arrows
(`→`) that Mukta lacks; `poppler` gives `pdfinfo`/`pdftoppm` for inspection.

**macOS (Homebrew)**
```bash
brew install uv pango gdk-pixbuf libffi cairo poppler
brew install --cask font-dejavu
```

**Windows (PowerShell + Chocolatey)**
```powershell
choco install -y uv poppler dejavufonts
# GTK3 runtime for WeasyPrint via MSYS2, then add C:\msys64\mingw64\bin to PATH:
# pacman -S mingw-w64-x86_64-pango mingw-w64-x86_64-gdk-pixbuf2
```

**Linux (apt)**
```bash
sudo apt-get update && sudo apt-get install -y libpango-1.0-0 libpangocairo-1.0-0 libgdk-pixbuf-2.0-0 libffi-dev libcairo2 fonts-liberation fonts-dejavu-core poppler-utils
curl -LsSf https://astral.sh/uv/install.sh | sh   # uv isn't in apt — skip if already installed
```

## 2. Python venv + MkDocs (run once)

**macOS / Linux (bash)**
```bash
B=/tmp/opda-pdf-build; uv venv "$B/.venv" && uv pip install --python "$B/.venv" mkdocs-material "mkdocs-with-pdf>=0.9"
```

**Windows (PowerShell)**
```powershell
$B="$env:TEMP\opda-pdf-build"; uv venv "$B\.venv"; uv pip install --python "$B\.venv" mkdocs-material "mkdocs-with-pdf>=0.9"
```

## 3. Build (re-run after editing Onboarding.md / mkdocs.yml / pdf.css)

**macOS / Linux (bash)** — set `S` to your `opda-ops` checkout
```bash
S=/path/to/opda-ops; B=/tmp/opda-pdf-build; rm -rf "$B/build" && mkdir -p "$B/build/docs" && cp "$S/docs-pdf/mkdocs.yml" "$B/build/mkdocs.yml" && cp "$S/docs-pdf/pdf.css" "$B/build/docs/pdf.css" && sed -E 's#\[\[([A-Za-z-]+)\]\]#[\1](https://github.com/Property-Data-Trust-Framework/opda-ops/wiki/\1)#g' "$S/wiki-seed/Onboarding.md" > "$B/build/docs/index.md" && (cd "$B/build" && ENABLE_PDF_EXPORT=1 "$B/.venv/bin/mkdocs" build)
```

**Windows (PowerShell)** — set `$S` to your `opda-ops` checkout
```powershell
$S="C:\path\to\opda-ops"; $B="$env:TEMP\opda-pdf-build"; Remove-Item -Recurse -Force "$B\build" -ErrorAction Ignore; New-Item -ItemType Directory -Force "$B\build\docs" | Out-Null; Copy-Item "$S\docs-pdf\mkdocs.yml" "$B\build\mkdocs.yml"; Copy-Item "$S\docs-pdf\pdf.css" "$B\build\docs\pdf.css"; ((Get-Content "$S\wiki-seed\Onboarding.md" -Raw) -replace '\[\[([A-Za-z-]+)\]\]','[$1](https://github.com/Property-Data-Trust-Framework/opda-ops/wiki/$1)') | Set-Content "$B\build\docs\index.md"; Push-Location "$B\build"; $env:ENABLE_PDF_EXPORT="1"; & "$B\.venv\Scripts\mkdocs.exe" build; Pop-Location
```

The `sed` / `-replace` step is the PDF-only wikilink rewrite — MkDocs doesn't grok
GitHub `[[wikilink]]` syntax, so they'd otherwise render as literal `[[Runbook]]` text.
The source keeps the `[[...]]` form (the wiki needs it). This mirrors the "Assemble"
step in `.github/workflows/onboarding-pdf.yml`.

## 4. Inspect (poppler — same tools on every OS)

```bash
pdfinfo /tmp/opda-pdf-build/build/site/pdf/onboarding.pdf
pdftoppm -png -r 110 /tmp/opda-pdf-build/build/site/pdf/onboarding.pdf /tmp/opda-pdf-png/page
```

## 5. Or just run the real pipeline

Builds from the **wiki** (needs it seeded) and publishes the `docs` release asset:

```bash
gh workflow run "Onboarding PDF" --repo Property-Data-Trust-Framework/opda-ops
```
