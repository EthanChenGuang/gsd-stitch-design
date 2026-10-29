#!/usr/bin/env bash
# Register the GSD project capability ui-stitch so /gsd-plan-phase and
# /gsd-autonomous run gsd-ui-stitch-phase after gsd-ui-phase (plan:pre).
# Also sets workflow.ui_stitch=true and workflow.ui_stitch_auto=false when unset.
#
# Usage: register-ui-stitch.sh <target-project-dir> [--dry-run]
# Intended for Cursor projects (GSD Core under .cursor/). Safe to re-run.
set -euo pipefail

USAGE="Usage: register-ui-stitch.sh <target-project-dir> [--dry-run]"

DRY=0
TARGET_ARG=""
while [ $# -gt 0 ]; do
  case "$1" in
    --dry-run) DRY=1 ;;
    -h|--help) printf '%s\n' "$USAGE"; exit 0 ;;
    -*) printf 'Unknown option: %s\n%s\n' "$1" "$USAGE" >&2; exit 2 ;;
    *)
      if [ -n "$TARGET_ARG" ]; then
        printf 'Only one target directory is allowed.\n%s\n' "$USAGE" >&2
        exit 2
      fi
      TARGET_ARG="$1"
      ;;
  esac
  shift
done

if [ -z "$TARGET_ARG" ]; then
  printf '%s\n' "$USAGE" >&2
  exit 2
fi
if [ ! -d "$TARGET_ARG" ]; then
  printf 'ERROR: target is not a directory: %s\n' "$TARGET_ARG" >&2
  exit 1
fi
TARGET="$(cd "$TARGET_ARG" && pwd -P)"

PACK_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd -P)"
CAP_ID="ui-stitch"
CAP_SRC="$PACK_DIR/capability/ui-stitch"
if [ ! -f "$CAP_SRC/capability.json" ]; then
  # Installed copy next to gsd-run: .cursor/bin/register-ui-stitch.sh
  if [ -f "$TARGET/.gsd/capabilities/ui-stitch/capability.json" ]; then
    CAP_SRC="$TARGET/.gsd/capabilities/ui-stitch"
  elif [ -f "$PACK_DIR/../capability/ui-stitch/capability.json" ]; then
    PACK_DIR="$(cd "$PACK_DIR/.." && pwd -P)"
    CAP_SRC="$PACK_DIR/capability/ui-stitch"
  fi
fi
if [ ! -f "$CAP_SRC/capability.json" ]; then
  printf 'ERROR: capability manifest not found (looked in pack and %s/.gsd/capabilities/ui-stitch).\n' "$TARGET" >&2
  exit 1
fi

resolve_gsd_tools() {
  GSD_TOOLS=""
  if [ -f "$TARGET/.cursor/gsd-core/bin/gsd-tools.cjs" ]; then
    GSD_TOOLS="$TARGET/.cursor/gsd-core/bin/gsd-tools.cjs"
  elif [ -f "$TARGET/.claude/gsd-core/bin/gsd-tools.cjs" ]; then
    GSD_TOOLS="$TARGET/.claude/gsd-core/bin/gsd-tools.cjs"
  elif [ -f "${CURSOR_CONFIG_DIR:-${HOME:-/nonexistent}/.cursor}/gsd-core/bin/gsd-tools.cjs" ]; then
    GSD_TOOLS="${CURSOR_CONFIG_DIR:-$HOME/.cursor}/gsd-core/bin/gsd-tools.cjs"
  elif [ -f "${HOME:-/nonexistent}/.claude/gsd-core/bin/gsd-tools.cjs" ]; then
    GSD_TOOLS="$HOME/.claude/gsd-core/bin/gsd-tools.cjs"
  fi
}

resolve_gsd_tools
if [ -z "$GSD_TOOLS" ]; then
  printf 'WARN: GSD gsd-tools.cjs not found; GSD capability %s not registered.\n' "$CAP_ID"
  exit 0
fi
if [ ! -d "$TARGET/.planning" ]; then
  printf 'WARN: %s has no .planning/ directory; GSD capability %s needs a GSD project root.\n' "$TARGET" "$CAP_ID"
  exit 0
fi

DRY_PREFIX=""
[ "$DRY" -eq 1 ] && DRY_PREFIX="[dry-run] "

if [ "$DRY" -eq 1 ]; then
  printf '%swould run: node %s capability install %s --scope project --yes --project-dir %s\n' "$DRY_PREFIX" "$GSD_TOOLS" "$CAP_SRC" "$TARGET"
else
  errf="$(mktemp "${TMPDIR:-/tmp}/gsd-sd-reg.XXXXXX")"
  rc=0
  out="$( cd "$TARGET" && node "$GSD_TOOLS" capability install "$CAP_SRC" --scope project --yes --project-dir "$TARGET" --pick status 2>"$errf" )" || rc=$?
  err="$(cat "$errf" 2>/dev/null || true)"
  rm -f "$errf"
  out="$(printf '%s' "$out" | tr -d '[:space:]')"
  if [ "$rc" -eq 0 ] && [ "$out" = "installed" ]; then
    printf '+ capability %s registered (project scope)\n' "$CAP_ID"
  elif [ "$rc" -eq 0 ]; then
    printf '= capability %s (%s)\n' "$CAP_ID" "${out:-ok}"
  else
    why="$(printf '%s\n' "$err" | grep -m1 . || true)"
    printf 'WARN: could not register GSD capability %s: %s\n' "$CAP_ID" "${why:-$out}"
  fi
fi

# workflow.ui_stitch=true, ui_stitch_auto=false (do not flip an existing true auto flag).
CONFIG="$TARGET/.planning/config.json"
if [ ! -f "$CONFIG" ]; then
  printf 'WARN: .planning/config.json not found; set workflow.ui_stitch=true by hand.\n'
  exit 0
fi

node -e '
const fs = require("fs");
const [dry, prefix, file] = process.argv.slice(1);
const say = (s) => console.log(prefix + s);
let obj;
try { obj = JSON.parse(fs.readFileSync(file, "utf8")); }
catch (e) {
  console.log("WARN: .planning/config.json is not valid JSON; set workflow.ui_stitch=true by hand.");
  process.exit(0);
}
if (obj === null || typeof obj !== "object" || Array.isArray(obj)) {
  console.log("WARN: .planning/config.json is not a JSON object; set workflow.ui_stitch=true by hand.");
  process.exit(0);
}
if (obj.workflow === null || typeof obj.workflow !== "object" || Array.isArray(obj.workflow)) obj.workflow = {};
const before = JSON.stringify(obj.workflow);
if (obj.workflow.ui_phase !== true) obj.workflow.ui_phase = true;
obj.workflow.ui_stitch = true;
if (!Object.prototype.hasOwnProperty.call(obj.workflow, "ui_stitch_auto")) obj.workflow.ui_stitch_auto = false;
if (JSON.stringify(obj.workflow) === before && obj.workflow.ui_stitch === true) {
  say("= .planning/config.json (workflow.ui_stitch already true)");
  process.exit(0);
}
if (dry !== "1") fs.writeFileSync(file, JSON.stringify(obj, null, 2) + "\n");
say("~ .planning/config.json (workflow.ui_stitch=true, ui_stitch_auto=" + String(obj.workflow.ui_stitch_auto) + ")");
' "$DRY" "$DRY_PREFIX" "$CONFIG"
