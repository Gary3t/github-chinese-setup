# Changelog

All notable changes to this project are documented here.
Format follows [Keep a Changelog](https://keepachangelog.com/); versioning follows [SemVer](https://semver.org/).

## [1.0.0] — 2026-10-13

First public release.

### Added

- **SKILL.md** — agent entry point covering a four-phase flow: recon → assisted install → precise manual-step guidance → verification.
- **Chrome 138+ gate handling** — detects Chrome version and branches accordingly. Below 138, developer mode suffices (1 manual step); 138 and above requires the per-extension **"Allow user scripts"** toggle (2 manual steps).
- **`scripts/diagnose.py`** — one-command state check across macOS / Windows / Linux. Reports extension state, the userscript gate, injection scope, and whether the userscript is still present in extension storage.
- **`scripts/setup-macos.sh`** — semi-automatic deploy: writes the external-extension declaration, enables developer mode, rescues open tabs, restarts Chrome, then prints the exact remaining manual steps. Supports `--check` (read-only) and `--yes`.
- **`scripts/export-for-agents.sh`** — exports portable `AGENTS.md` / `GEMINI.md` forms for hosts without a skills concept.
- **`references/gotchas.md`** — 10 field-tested traps.
- **`references/recipes.md`** — green / yellow / red recipe grading plus source-vetting criteria.
- **`docs/chrome-userscript-guide.html`** — self-contained guide for machines with no agent.

### Documented traps (the reason this exists)

- Editing `Secure Preferences` triggers an HMAC check that wipes the value, **disables the extension, and clears its storage — losing every installed userscript.**
- `open` cannot launch `chrome://` or `chrome-extension://` URLs on macOS.
- AppleScript UI automation of `chrome://extensions` is blocked (`-10004`).
- CDP is disabled on the default profile in Chrome 136+.
- Chrome's UI language follows the OS locale, so node names like `Principled BSDF` may be localized — match by type instead of name.

### Known limitations

- **Three steps require the user personally.** The browser is designed this way; no policy, CLI flag, or automation bypasses it.
- Windows deploy script is not included yet (`diagnose.py` is cross-platform; `setup-macos.sh` is macOS-only).
- Metadata is Chinese-first; English search visibility is limited.
