<!-- gsd-stitch-design:start -->
## UI Design Workflow (overrides GSD's default UI step)

In this project, `/gsd-ui-stitch-phase` **replaces** `/gsd-ui-phase` everywhere it would normally run:

- When a GSD workflow or status output recommends `/gsd-ui-phase {N}`, for example `/gsd-next`, `/gsd-progress`, the "Next Up" block after `/gsd-discuss-phase`, or the UI gate before `/gsd-plan-phase`, run `/gsd-ui-stitch-phase {N}` instead and tell the user you did so. It calls `/gsd-ui-phase` internally with all its gates, then adds the global design check, screen generation (Google Stitch or the html renderer) and export.
- If the user types `/gsd-ui-phase` directly, ask whether they want the full `/gsd-ui-stitch-phase` flow or only the UI-SPEC (no screen generation).
- The pack registers the GSD capability `ui-stitch`, so `/gsd-autonomous` and `/gsd-plan-phase --auto` run `gsd-ui-stitch-phase` right after `gsd-ui-phase` for frontend phases. When the `plan:pre` hooks dispatch both skills, run each one as dispatched and do not swap the `gsd-ui-phase` dispatch for `gsd-ui-stitch-phase`; the redirect rule above applies only to recommendations. Register once per machine, cloud session or moved checkout with `install.sh <dir> --register-only`. Turn it off with `workflow.ui_stitch=false`. `workflow.ui_stitch_auto=true` makes hook runs non-interactive.
- The project-wide design system lives in `.planning/design/DESIGN.md` and is the single source for design tokens. Never change tokens inside a phase. Change them only through the skill's global-change step (G4).
- To find a starting template for the global design, run `/gsd-ui-design-pick`. It picks a DESIGN.md from VoltAgent/awesome-design-md based on the planning docs, then hands the pick to `/gsd-ui-stitch-phase` for review, de-branding and locking. Every template there is modeled on a real brand, so never lock one as-is.
- Keep `workflow.ui_phase` set to `true` in `.planning/config.json`. `/gsd-ui-stitch-phase` depends on `/gsd-ui-phase`, which exits early when that flag is off.
- Project-specific values (product name, languages, device, viewport, stack, brand exclusions, renderer) live in `.planning/design/design-config.json`. The skills read them from there; edit that file instead of the skills.
- G4 global-change proposals are written to `.planning/design/DESIGN-CHANGE-v{n}.md` and need user approval before DESIGN.md changes.
- Per-phase designs live in `.planning/phases/{NN}-{slug}/design/` (`manifest.json` plus html and png files) and are the visual reference for plan-phase and execute-phase. Planners cite the relevant screens in task actions, executors match the screenshots, token values come from DESIGN.md and copy and states come from the phase UI-SPEC.
<!-- gsd-stitch-design:end -->
