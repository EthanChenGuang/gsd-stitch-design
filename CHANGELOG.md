# Changelog

All notable changes to the gsd-stitch-design pack are recorded here. The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

## [1.5.0] - 2026-10-23

Fixes from installing the pack in a project behind a stricter proxy, with a different GSD version.

### Fixed

- Downloads go through git (`git ls-remote` for the newest release, `git clone --depth 1 --branch`), with the release tarball only as a fallback, so the install works where the proxy blocks GitHub release downloads. Running `bootstrap.sh` from a clone of this repository uses that clone and downloads nothing.
- Registration no longer fails on GSD versions without a step that produces `UI-SPEC.md`: when GSD refuses the step's declared input, the installer registers it again without inputs and prints a NOTE. The skill creates `UI-SPEC.md` itself (through `/gsd-ui-phase`) when it is missing.
- The SessionStart hook no longer downloads and runs a script. It re-registers from the copy committed in the project (`.gsd/capabilities/ui-stitch/`) with the project's own GSD, and keeps the committed ledger.

### Changed

- The README's main command is `git clone ... && bash .../bootstrap.sh`; `curl | bash` stays as an alternative.

## [1.4.1] - 2026-10-23

### Changed

- `bootstrap.sh` checks for GSD (`.claude/gsd-core` in the project or `~/.claude`, or `gsd_run`) and for `.planning/config.json` before downloading anything. When either is missing it writes nothing, exits 1 and prints what is missing and how to fix it; `--skip-gsd-check` installs anyway. Before, it warned and carried on, ending with "done".

### Added

- README section with the steps Claude follows when asked to install the pack from this repository's URL.

## [1.4.0] - 2026-10-23

### Added

- `bootstrap.sh` adds a SessionStart hook (`.claude/hooks/gsd-stitch-design.sh`, registered in `.claude/settings.json`) that re-registers the `ui-stitch` capability in fresh Claude cloud containers and does nothing on a local machine. `--no-hook` skips it; `--uninstall` removes it.

### Changed

- Install and registration are two steps: run the one command, then commit and push. The README leads with them and keeps every other operation as a flag of the same command.

## [1.3.0] - 2026-10-21

### Added

- `bootstrap.sh`: one command (`curl -fsSL .../bootstrap.sh | bash`) that fetches the latest release, installs, registers the `ui-stitch` capability and stages every file to commit, including the `-f` one. Flags pass through to `install.sh`; `GSD_STITCH_REF` pins a version. Releases are cached under `~/.cache/gsd-stitch-design/<tag>`.
- CI runs the bootstrap against a temporary project.

### Changed

- The README leads with the one-command install; the clone-and-run steps stay as the manual method.

## [1.2.0] - 2026-10-21

The pack now lives in its own repository, so projects no longer need the source project to install it.

### Changed

- Install from `https://github.com/EthanChenGuang/gsd-stitch-design` at a fixed tag; every command in the README runs from the pack root.
- The README has a section on re-registering the capability from a cloud SessionStart hook, with a vendored copy or a pinned clone.
- Notes that named the source project are worded neutrally; the filled example in `templates/design-config.example.json` keeps its values as an example.

### Added

- GitHub Actions workflow that runs `test/install.test.sh` on every push and pull request.
- Release workflow: a push to `main` that names a new version in `VERSION` publishes the `v<VERSION>` tag and release, with that version's CHANGELOG section as the notes.

## [1.1.1] - 2026-10-20

Fixes found while migrating Parla: wrong commit guidance for the registration files, and a dirty ledger after every fresh-session re-registration.

### Fixed

- The commit guidance in the install next steps and the README now uses `git add -f .gsd/capabilities/ui-stitch/capability.json` and explains GSD's `.gsd/.gitignore` (content `*`), which makes a plain `git add` skip that file. It tells users never to edit that `.gitignore`.
- Re-registration no longer leaves a git-tracked `.gsd-capabilities.json` dirty when only the top-level `updatedAt` or the entry `source` changed. The installer restores the committed version and prints `=`; real changes such as a version bump are kept and printed with `~`; `--dry-run` only reports that the check would run. The check uses read-only git plumbing, so no repository hooks run.

### Added

- `gsd-ui-stitch-phase` fetches Stitch screen files with the Stitch MCP tool `download_file` (names taken from `get_screen` `htmlCode.name` and `screenshot.name`; the base64 image is decoded with `base64 -d`), in step X and in the renderer=auto E1 probe. `curl` on `downloadUrl` stays only as a fallback when `download_file` is unavailable, because those URLs need credentials and returned 401 in Parla.
- Test scenario G (git-tracked ledger in fresh clones): both files committed, a second pack path, dry-run, version change, uninstall, a ledger-only clone and a nothing-committed clone.

### Changed

- The README sections 安装器会改什么 and 接入 /gsd-autonomous describe the restore, the three fresh-clone outcomes and the SessionStart hook without a git step. The capability manifest version now follows `VERSION`.

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
