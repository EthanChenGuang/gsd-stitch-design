# Changelog

All notable changes to the gsd-stitch-design pack are recorded here. The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

## [1.1.0] - 2026-10-19

Registers the pack as a GSD project capability so that autonomous runs produce the screen designs too.

### Added

- GSD capability `ui-stitch` (`capability/ui-stitch/capability.json`): a `plan:pre` step that dispatches `gsd-ui-stitch-phase` after GSD's own `gsd-ui-phase` (produces `SCREENS.md`, consumes `UI-SPEC.md`), plus a planner contribution that points the planner at the screen designs. Config keys `workflow.ui_stitch` (default true) and `workflow.ui_stitch_auto` (default false).
- `install.sh` registers the capability (project scope) after copying the skills, and WARNs without failing when GSD, `.planning/` or the registration is missing. New flags: `--no-autonomous` (skip registration), `--register-only` (re-register on a new machine or cloud session; copies and edits nothing else). `--uninstall` removes the registration. `--dry-run` prints the registration command. The next-steps text names the files to commit and the per-machine consent record.
- `gsd-ui-stitch-phase`: hook entry (UI-SPEC exists, SCREENS.md missing: skip A, run B', continue from C) and an auto mode (`--auto`, or `workflow.ui_stitch_auto=true`) that takes the recommended option at every gate, never applies G4, and warns and exits normally when the global DESIGN.md is missing or not locked. Interactive behavior is unchanged.
- README section 接入 /gsd-autonomous: behavior table, switching it off, the per-machine consent caveat with a SessionStart snippet, and the limits of the hook path.
- Integration tests (scenarios D and F) that install into a temp GSD project with an isolated `GSD_HOME` and check the hooks GSD renders for `plan:pre`.

### Changed

- The `CLAUDE.md` block no longer says that `/gsd-autonomous` bypasses the override; it describes the registered capability instead.

## [1.0.0] - 2026-10-19

First packaged release. Extracted from the Parla project's own `gsd-ui-stitch-phase` and `gsd-ui-design-pick` skills and made generic.

### Added

- `gsd-ui-stitch-phase` skill: global design system (`.planning/design/DESIGN.md`) plus per-phase UI-SPEC and screen designs. Every project-specific value (product name, pitch, audience, languages, device, viewport, stack, brand exclusions, font rules, extra review checks) is read from `.planning/design/design-config.json` instead of being hardcoded.
- Renderer choice `auto | stitch | html` (`--renderer` argument or `renderer` in the config). `auto` probes whether Stitch files can be fetched and offers the html renderer when they cannot. The html renderer builds `design/tokens.css` from DESIGN.md, writes standalone HTML screens and renders PNGs with Playwright. The chosen renderer is recorded in each phase `manifest.json`.
- G4 global-change proposals are written to `.planning/design/DESIGN-CHANGE-v{n}.md` with an approval status.
- Pre-flight warning when the Stitch design system (`stitch.json` `design_version`) lags behind DESIGN.md, and a version check for `tokens.css`.
- Portable GSD tool resolution (`.claude/gsd-core`, then `$HOME/.claude/gsd-core`, then `gsd_run` on PATH) and skill-directory resolution (project, then `$HOME`).
- `gsd-ui-design-pick` skill: picks a starting DESIGN.md template from VoltAgent/awesome-design-md using a brief built from the config and planning docs; preview content comes from `preview_samples`, exclusions from `brand_exclusions`.
- Three bundled scripts: `shoot.cjs` (Playwright HTML to PNG with `--width --height --scale --wait --check`), `contrast.cjs` (WCAG contrast CLI with `--json`), `design-catalog.cjs` (awesome-design-md catalog parser).
- `install.sh <project-dir> [--dry-run] [--force] [--uninstall]`: copies both skills, creates `design-config.json` only when absent, adds an idempotent marker-bounded section to `CLAUDE.md`, sets `workflow.ui_phase=true`, writes a version file, refuses to overwrite locally edited skill files without `--force` (exit 3).
- Templates: `design-config.json` (with per-field comments), `design-config.example.json` (a filled example), `CLAUDE-section.md`.
- `test/install.test.sh`: end-to-end test covering syntax checks, script smoke tests and install, idempotency, dry-run, conflict, force and uninstall scenarios.
- Chinese `README.md`.
