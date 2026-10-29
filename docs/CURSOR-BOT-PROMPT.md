# Cursor bot prompt: install gsd-stitch-design into this repo

Copy everything below the line into a Cursor cloud agent / coding bot that is working **in the target project** (not in this pack). The bot should open a PR. It must not push to `main`, force-push, merge, or publish a release.

---

Install the **gsd-stitch-design** pack (Cursor support, pack version 1.6.0+) into THIS repository so the Cursor agent can run `gsd-ui-design-pick` and `gsd-ui-stitch-phase` with GSD Core for Cursor.

Work on a new feature branch. Open a PR into the repo’s default branch. Never push to `main`, never force-push, never merge, never publish a release. Do not modify any other repository.

## Prerequisites (stop if missing)

1. **GSD Core for Cursor** is already installed in this repo under `.cursor/` (you should see `.cursor/gsd-core/bin/gsd-tools.cjs` and `.cursor/skills/gsd-*`). It should be 1.19.0 or newer. If GSD is missing, stop and report: the human must run `npx -y @opengsd/gsd-core@latest --cursor --local` (or their equivalent) first. Do not install GSD yourself unless the user explicitly asked you to.
2. This is a GSD project: `.planning/config.json` exists. If `.planning/` is missing, stop and report: run `gsd-new-project` first, then retry.
3. **Google Stitch API key** is required to actually generate screens. You will **not** create or commit a key.

### API key (required for Stitch; never commit it)

- Create a Google Stitch API key at https://stitch.withgoogle.com/settings (API Keys) while signed in as the **Google account that owns this project’s Stitch project**.
- Set it as the environment variable **`STITCH_API_KEY`**.
  - Cursor Cloud Agents: add a secret named `STITCH_API_KEY` at https://cursor.com/dashboard?tab=cloud-agents
  - Cursor desktop: set it in the local environment (shell env, direnv, etc.)
- The installer writes `.cursor/mcp.json` with header `X-Goog-Api-Key: ${env:STITCH_API_KEY}`. That substitution reads the env var at runtime. **Never paste the key into a file, commit, PR, log, or chat.**

If `STITCH_API_KEY` is not set in this environment, still install the pack. Do **not** call Stitch. After install, report that screens cannot be generated until the secret is set.

## Steps

1. Confirm the prerequisites above. Record GSD version from `.cursor/gsd-core/VERSION`.
2. Create a feature branch off the default branch (do not commit on `main`).
3. Fetch the pack (git only; do not curl GitHub release tarballs if a proxy might block them):

   ```bash
   rm -rf /tmp/gsd-stitch-design
   git clone --depth 1 https://github.com/EthanChenGuang/gsd-stitch-design /tmp/gsd-stitch-design
   ```

   To pin a release: `git clone --depth 1 --branch v1.6.0 https://github.com/EthanChenGuang/gsd-stitch-design /tmp/gsd-stitch-design`

4. Preview, then install for Cursor (idempotent; safe to run twice):

   ```bash
   bash /tmp/gsd-stitch-design/install.sh "$(git rev-parse --show-toplevel)" --cursor --dry-run
   bash /tmp/gsd-stitch-design/install.sh "$(git rev-parse --show-toplevel)" --cursor
   ```

   Equivalent one-liner from a clone of the pack:

   ```bash
   bash /tmp/gsd-stitch-design/bootstrap.sh --cursor
   ```

   If this repo already has a Claude install of the pack, leave `.claude/skills/` untouched. `--cursor` only writes Cursor paths.

5. If `.planning/design/design-config.json` was just created, fill `product_name`, `product_pitch`, `audience`, `ui_language` from this project’s planning docs. Do **not** overwrite an existing design-config. Cursor installs default `"renderer": "stitch"` on a **new** file only. Do not copy product ids, Stitch project ids, or design-system ids from any other repo (including paperpro).

6. Commit only the files the installer staged / wrote, for example:

   - `.cursor/skills/gsd-ui-stitch-phase/`
   - `.cursor/skills/gsd-ui-design-pick/`
   - `.cursor/skills/.gsd-stitch-design-version`
   - `.cursor/mcp.json` (must stay valid JSON; must contain `mcpServers.Google_Stitch`; must **not** contain a literal API key)
   - `.cursor/rules/gsd-stitch-design.mdc`
   - `.cursor/bin/gsd-run`
   - `.cursor/bin/register-ui-stitch.sh`
   - `.planning/design/design-config.json` (only if newly created or you filled empty required fields)
   - `.planning/config.json` (`workflow.ui_phase: true`, `workflow.ui_stitch: true`, `ui_stitch_auto: false` unless it was already true)
   - `.gsd-capabilities.json` and `git add -f .gsd/capabilities/ui-stitch/capability.json`

7. Push the feature branch and open a PR to the default branch.

## Verification (do this in the target repo)

- `.cursor/skills/gsd-ui-stitch-phase/SKILL.md` and `gsd-ui-design-pick/SKILL.md` exist.
- `.cursor/skills/.gsd-stitch-design-version` matches the pack `VERSION` (1.6.0 or newer).
- `.cursor/mcp.json` parses as JSON. It has `mcpServers.Google_Stitch` with `url` `https://stitch.googleapis.com/mcp` and header `X-Goog-Api-Key` equal to `${env:STITCH_API_KEY}`. Other MCP servers that were already there are still there. No API key string is in the file.
- `.cursor/bin/gsd-run` is executable. Running it without GSD should fail with an install hint; with GSD it should reach `gsd-tools`.
- `.cursor/rules/gsd-stitch-design.mdc` exists and mentions the GSD 1.19.0 workaround: if `{NN}-SCREENS.md` is missing, still run `gsd-ui-stitch-phase` even when UI-SPEC exists.
- `.planning/config.json` has `workflow.ui_stitch: true`.
- Re-run `install.sh --cursor` a second time: no unexpected diffs (idempotent).
- Do **not** call Google Stitch (no `GetDynamicTools` / `CallDynamicTool` against `Google_Stitch`) unless `STITCH_API_KEY` is set **and** the user asked you to generate screens in this same task.

Expected Stitch MCP tool names (14), used via Cursor MCP namespace `Google_Stitch` (not Claude `mcp__Google_Stitch__*`):

1. `create_project`
2. `get_project`
3. `list_projects`
4. `generate_screen_from_text`
5. `get_screen`
6. `list_screens`
7. `edit_screens`
8. `generate_variants`
9. `upload_design_md`
10. `create_design_system_from_design_md`
11. `list_design_systems`
12. `apply_design_system`
13. `update_design_system`
14. `download_file`

## What not to do

- Do not push to `main`, force-push, merge the PR, or create a GitHub release / tag.
- Do not commit `STITCH_API_KEY` or any Google credential.
- Do not clobber unrelated servers in `.cursor/mcp.json`.
- Do not overwrite `.planning/design/design-config.json` if it already exists.
- Do not copy skills from another product repo. Install from `EthanChenGuang/gsd-stitch-design` only.
- Do not put paperpro (or any other project’s) Stitch project id, design-system id, or product strings into this pack install.
- Do not silently fall back to the html renderer when Stitch is missing; `renderer` is `stitch`. Stop and report.
- Do not use Claude-only tools (`AskUserQuestion`, `SendUserFile`, `ToolSearch`, `mcp__Google_Stitch__*`, `Agent`, `Skill`).
- When no interactive user can reply, do not silently pick a non-recommended option. Stop, commit and push, and report the exact question, options, and recommended option.
- Do not change GSD Core files under `.cursor/gsd-core/` except by the official GSD installer.
- Do not uninstall the Claude copy of this pack unless asked (`install.sh --uninstall` without `--cursor` is Claude-only).
