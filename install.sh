#!/usr/bin/env bash
# gsd-stitch-design installer.
# Installs the gsd-ui-stitch-phase and gsd-ui-design-pick skills into another GSD project.
# It also registers the GSD project capability ui-stitch, so /gsd-autonomous and
# /gsd-plan-phase --auto run gsd-ui-stitch-phase after gsd-ui-phase.
# Usage: install.sh <target-project-dir> [--dry-run] [--force] [--uninstall]
#                   [--no-autonomous | --register-only]
set -euo pipefail

USAGE="Usage: install.sh <target-project-dir> [--dry-run] [--force] [--uninstall]
                          [--no-autonomous | --register-only]

  --dry-run         print what would happen, change nothing
  --force           overwrite installed skill files that differ from the pack
                    (ignored with --register-only)
  --uninstall       remove the two skills, the CLAUDE.md block, the version file
                    and the GSD capability registration
                    (.planning/design and workflow.ui_phase are left as-is)
  --no-autonomous   do not register the GSD capability ui-stitch
  --register-only   only (re)register the GSD capability ui-stitch (new machine /
                    cloud session); copies and edits nothing else
  -h, --help        show this help

Exit codes: 0 ok, 1 error, 2 usage error, 3 refused because of conflicts"

DRY=0
FORCE=0
UNINSTALL=0
NO_AUTO=0
REGISTER_ONLY=0
TARGET_ARG=""

while [ $# -gt 0 ]; do
  case "$1" in
    --dry-run) DRY=1 ;;
    --force) FORCE=1 ;;
    --uninstall) UNINSTALL=1 ;;
    --no-autonomous) NO_AUTO=1 ;;
    --register-only) REGISTER_ONLY=1 ;;
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

if [ "$REGISTER_ONLY" -eq 1 ] && [ "$UNINSTALL" -eq 1 ]; then
  printf '%s\n%s\n' "--register-only cannot be combined with --uninstall." "$USAGE" >&2
  exit 2
fi
if [ "$REGISTER_ONLY" -eq 1 ] && [ "$NO_AUTO" -eq 1 ]; then
  printf '%s\n%s\n' "--register-only cannot be combined with --no-autonomous." "$USAGE" >&2
  exit 2
fi

PACK_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"

if [ ! -d "$TARGET_ARG" ]; then
  printf 'ERROR: target is not a directory: %s\n' "$TARGET_ARG" >&2
  exit 1
fi
TARGET="$(cd "$TARGET_ARG" && pwd -P)"

if ! command -v node >/dev/null 2>&1; then
  printf 'ERROR: node is required but was not found on PATH.\n' >&2
  exit 1
fi

DRY_PREFIX=""
if [ "$DRY" -eq 1 ]; then
  DRY_PREFIX="[dry-run] "
fi

# act <line>: print an action line (prefixed in dry-run mode).
act() {
  printf '%s%s\n' "$DRY_PREFIX" "$1"
}

SKILLS_REL=".claude/skills"
SKILL_NAMES="gsd-ui-stitch-phase gsd-ui-design-pick"
VERSION_REL=".claude/skills/.gsd-stitch-design-version"
DESIGN_CONFIG_REL=".planning/design/design-config.json"
CLAUDE_CANDIDATES_REL=".claude/CLAUDE.md CLAUDE.md"
PACK_VERSION="$(tr -d '[:space:]' < "$PACK_DIR/VERSION")"
CAP_ID="ui-stitch"
CAP_SRC="$PACK_DIR/capability/ui-stitch"
CAP_STAGED_REL=".gsd/capabilities/ui-stitch"
LEDGER_REL=".gsd-capabilities.json"

# ---------------------------------------------------------------------------
# node helpers (paths and content are passed as argv, never interpolated)
# ---------------------------------------------------------------------------

CLAUDE_JS=$(cat <<'EOF'
// argv: mode(install|uninstall) dry(0|1) prefix templatePath targetDir candidateRel...
const fs = require('fs');
const path = require('path');
const [mode, dry, prefix, templatePath, targetDir, ...rels] = process.argv.slice(1);
const START = '<!-- gsd-stitch-design:start -->';
const END = '<!-- gsd-stitch-design:end -->';
const isDry = dry === '1';
const say = (s) => console.log(prefix + s);

function findBlock(text, rel) {
  const s = text.indexOf(START);
  const e = text.indexOf(END);
  if (s === -1 && e === -1) return null;
  if (s === -1 || e === -1 || e < s) {
    console.error('ERROR: ' + rel + ' has an unbalanced gsd-stitch-design marker; fix it by hand first.');
    process.exit(1);
  }
  let end = e + END.length;
  if (text[end] === '\r') end += 1;
  if (text[end] === '\n') end += 1;
  return { start: s, end };
}

const files = rels
  .map((rel) => ({ rel, abs: path.join(targetDir, rel) }))
  .filter((f) => fs.existsSync(f.abs) && fs.statSync(f.abs).isFile());

if (mode === 'install') {
  const template = fs.readFileSync(templatePath, 'utf8');
  const withBlock = [];
  for (const f of files) {
    const text = fs.readFileSync(f.abs, 'utf8');
    const b = findBlock(text, f.rel);
    if (b) withBlock.push({ f, text, b });
  }
  if (withBlock.length > 0) {
    for (const { f, text, b } of withBlock) {
      const next = text.slice(0, b.start) + template + text.slice(b.end);
      if (next === text) {
        say('= ' + f.rel + ' (UI Design Workflow block unchanged)');
      } else {
        if (!isDry) fs.writeFileSync(f.abs, next);
        say('~ ' + f.rel + ' (UI Design Workflow block updated)');
      }
    }
  } else if (files.length > 0) {
    const f = files[0];
    let text = fs.readFileSync(f.abs, 'utf8');
    let next;
    if (text.length === 0) {
      next = template;
    } else {
      if (!text.endsWith('\n')) text += '\n';
      next = text + '\n' + template;
    }
    if (!isDry) fs.writeFileSync(f.abs, next);
    say('~ ' + f.rel + ' (UI Design Workflow block added)');
  } else {
    const rel = '.claude/CLAUDE.md';
    const abs = path.join(targetDir, rel);
    if (!isDry) {
      fs.mkdirSync(path.dirname(abs), { recursive: true });
      fs.writeFileSync(abs, template);
    }
    say('+ ' + rel + ' (created with UI Design Workflow block)');
  }
} else {
  let any = false;
  for (const f of files) {
    const text = fs.readFileSync(f.abs, 'utf8');
    const b = findBlock(text, f.rel);
    if (!b) continue;
    any = true;
    let start = b.start;
    if (start >= 2 && text[start - 1] === '\n' && text[start - 2] === '\n') start -= 1;
    const next = text.slice(0, start) + text.slice(b.end);
    if (next.trim() === '') {
      if (!isDry) fs.unlinkSync(f.abs);
      say('- ' + f.rel + ' (removed, nothing left after removing the block)');
    } else {
      if (!isDry) fs.writeFileSync(f.abs, next);
      say('- ' + f.rel + ' (UI Design Workflow block removed)');
    }
  }
  if (!any) say('= no UI Design Workflow block found in CLAUDE.md');
}
EOF
)

PLANNING_JS=$(cat <<'EOF'
// argv: dry(0|1) prefix configPath
const fs = require('fs');
const [dry, prefix, file] = process.argv.slice(1);
const say = (s) => console.log(prefix + s);
let obj;
try {
  obj = JSON.parse(fs.readFileSync(file, 'utf8'));
} catch (e) {
  console.log('WARN: .planning/config.json is not valid JSON; set workflow.ui_phase=true by hand.');
  process.exit(0);
}
if (obj === null || typeof obj !== 'object' || Array.isArray(obj)) {
  console.log('WARN: .planning/config.json is not a JSON object; set workflow.ui_phase=true by hand.');
  process.exit(0);
}
if (obj.workflow && typeof obj.workflow === 'object' && obj.workflow.ui_phase === true) {
  say('= .planning/config.json (workflow.ui_phase already true)');
  process.exit(0);
}
if (obj.workflow === null || typeof obj.workflow !== 'object' || Array.isArray(obj.workflow)) obj.workflow = {};
obj.workflow.ui_phase = true;
if (dry !== '1') fs.writeFileSync(file, JSON.stringify(obj, null, 2) + '\n');
say('~ .planning/config.json (workflow.ui_phase set to true)');
EOF
)

CAP_ACTIVE_JS=$(cat <<'EOF'
// argv: capabilityId listJson. Exit 0 when the capability is listed with status "active", else 1.
const [id, raw] = process.argv.slice(1);
let list;
try {
  list = JSON.parse(raw);
} catch (e) {
  process.exit(1);
}
const hit = Array.isArray(list) && list.some((e) => e && e.id === id && e.status === 'active');
process.exit(hit ? 0 : 1);
EOF
)

LEDGER_JS=$(cat <<'EOF'
// argv: headFile workFile
// Exit 0 when the two ledgers are equal after dropping the volatile fields, 1 when they differ,
// 2 when either file is not a parsable plain JSON object.
const fs = require('fs');
// Volatile fields: the only ledger fields that differ between registrations of the same
// manifest from two pack paths (verified against GSD 1.17.0). version, integrity, files
// and sharedEdits are real content and must never be added here.
const VOLATILE_TOP = ['updatedAt'];
const VOLATILE_ENTRY = ['source'];
const isObj = (v) => v !== null && typeof v === 'object' && !Array.isArray(v);
function load(file) {
  let v;
  try {
    v = JSON.parse(fs.readFileSync(file, 'utf8'));
  } catch (e) {
    process.exit(2);
  }
  if (!isObj(v)) process.exit(2);
  return v;
}
function normalize(v) {
  const c = JSON.parse(JSON.stringify(v));
  for (const k of VOLATILE_TOP) delete c[k];
  if (isObj(c.entries)) {
    for (const id of Object.keys(c.entries)) {
      if (isObj(c.entries[id])) for (const k of VOLATILE_ENTRY) delete c.entries[id][k];
    }
  }
  return c;
}
function stable(v) {
  if (Array.isArray(v)) return '[' + v.map(stable).join(',') + ']';
  if (isObj(v)) return '{' + Object.keys(v).sort().map((k) => JSON.stringify(k) + ':' + stable(v[k])).join(',') + '}';
  return JSON.stringify(v);
}
const [headFile, workFile] = process.argv.slice(1);
const a = load(headFile);
const b = load(workFile);
process.exit(stable(normalize(a)) === stable(normalize(b)) ? 0 : 1);
EOF
)

# ---------------------------------------------------------------------------
# GSD capability registration
# ---------------------------------------------------------------------------

RESULT=""      # registered | active | skipped | failed (set by register_capability)
GSD_TOOLS=""

# resolve_gsd_tools: project copy first, then $HOME. No PATH lookup.
resolve_gsd_tools() {
  GSD_TOOLS=""
  if [ -f "$TARGET/.claude/gsd-core/bin/gsd-tools.cjs" ]; then
    GSD_TOOLS="$TARGET/.claude/gsd-core/bin/gsd-tools.cjs"
  elif [ -f "${HOME:-/nonexistent}/.claude/gsd-core/bin/gsd-tools.cjs" ]; then
    GSD_TOOLS="$HOME/.claude/gsd-core/bin/gsd-tools.cjs"
  fi
}

# first_line <text>: first non-empty line of text.
first_line() {
  printf '%s\n' "$1" | grep -m1 . || true
}

print_reregister_hint() {
  printf 'Re-register on another machine / cloud session: bash %q %q --register-only\n' "$PACK_DIR/install.sh" "$TARGET"
}

# restore_volatile_ledger: when .gsd-capabilities.json is tracked by git and the fresh
# registration changed only volatile fields (updatedAt, entry source), put the committed
# bytes back so the work tree stays clean. Read-only git plumbing plus a plain file write:
# no checkout/restore/status, so no repo hooks run and dry-run writes nothing. Never fails.
restore_volatile_ledger() {
  command -v git >/dev/null 2>&1 || return 0
  local inside="" prefix="" head_id="" index_id="" tmp="" rc=0 keep_line
  inside="$(git -C "$TARGET" rev-parse --is-inside-work-tree 2>/dev/null || true)"
  [ "$inside" = "true" ] || return 0
  prefix="$(git -C "$TARGET" rev-parse --show-prefix 2>/dev/null || true)"
  head_id="$(git -C "$TARGET" rev-parse -q --verify "HEAD:${prefix}${LEDGER_REL}" 2>/dev/null || true)"
  [ -n "$head_id" ] || return 0
  if [ "$DRY" -eq 1 ]; then
    printf '%swould restore %s from HEAD if only volatile fields change\n' "$DRY_PREFIX" "$LEDGER_REL"
    return 0
  fi
  [ -f "$TARGET/$LEDGER_REL" ] || return 0
  keep_line="~ $LEDGER_REL (registration changed; kept, commit it)"
  index_id="$(git -C "$TARGET" rev-parse -q --verify ":${prefix}${LEDGER_REL}" 2>/dev/null || true)"
  if [ "$index_id" != "$head_id" ]; then
    printf '%s\n' "$keep_line"
    return 0
  fi
  tmp="$(mktemp "${TMPDIR:-/tmp}/gsd-sd-ledger.XXXXXX")"
  if git -C "$TARGET" cat-file blob "$head_id" > "$tmp" 2>/dev/null; then
    node -e "$LEDGER_JS" "$tmp" "$TARGET/$LEDGER_REL" 2>/dev/null || rc=$?
  else
    rc=2
  fi
  if [ "$rc" -eq 0 ]; then
    cat "$tmp" > "$TARGET/$LEDGER_REL" || true
    printf '= %s (only volatile fields changed; restored)\n' "$LEDGER_REL"
  else
    printf '%s\n' "$keep_line"
  fi
  rm -f "$tmp"
  return 0
}

# register_capability: never fails the script; sets RESULT.
register_capability() {
  RESULT=""
  if [ "$NO_AUTO" -eq 1 ]; then
    RESULT="skipped"
    printf '= capability %s (registration skipped, --no-autonomous)\n' "$CAP_ID"
    return 0
  fi
  resolve_gsd_tools
  if [ -z "$GSD_TOOLS" ]; then
    RESULT="failed"
    printf 'WARN: GSD gsd-tools.cjs not found; GSD capability %s not registered (/gsd-autonomous will not run gsd-ui-stitch-phase).\n' "$CAP_ID"
    return 0
  fi
  if [ ! -d "$TARGET/.planning" ]; then
    RESULT="failed"
    printf 'WARN: %s has no .planning/ directory; GSD capability %s needs a GSD project root. Rerun after /gsd-new-project.\n' "$TARGET" "$CAP_ID"
    return 0
  fi
  if [ "$DRY" -eq 1 ]; then
    printf '%swould run: node %s capability install %s --scope project --yes --project-dir %s\n' "$DRY_PREFIX" "$GSD_TOOLS" "$CAP_SRC" "$TARGET"
    restore_volatile_ledger
    return 0
  fi

  local staged="$TARGET/$CAP_STAGED_REL/capability.json" had_staged=0 list_json="" out="" rc=0 errf="" err=""
  [ -f "$staged" ] && had_staged=1
  if [ "$had_staged" -eq 1 ] && cmp -s "$CAP_SRC/capability.json" "$staged"; then
    list_json="$(node "$GSD_TOOLS" capability list --project-dir "$TARGET" 2>/dev/null || true)"
    if [ -n "$list_json" ] && node -e "$CAP_ACTIVE_JS" "$CAP_ID" "$list_json" 2>/dev/null; then
      RESULT="active"
      printf '= capability %s (registered, active)\n' "$CAP_ID"
      return 0
    fi
  fi

  errf="$(mktemp "${TMPDIR:-/tmp}/gsd-sd-cap.XXXXXX")"
  out="$( cd "$TARGET" && node "$GSD_TOOLS" capability install "$CAP_SRC" --scope project --yes --project-dir "$TARGET" --pick status 2>"$errf" )" || rc=$?
  err="$(cat "$errf" 2>/dev/null || true)"
  rm -f "$errf"
  out="$(printf '%s' "$out" | tr -d '[:space:]')"
  if [ "$rc" -eq 0 ] && [ "$out" = "installed" ]; then
    if [ "$had_staged" -eq 1 ]; then
      RESULT="registered"
      printf '~ capability %s re-registered (project scope)\n' "$CAP_ID"
    else
      RESULT="registered"
      printf '+ capability %s registered (project scope)\n' "$CAP_ID"
    fi
    restore_volatile_ledger
  else
    RESULT="failed"
    local why
    why="$(first_line "$err")"
    [ -n "$why" ] || why="$out"
    printf 'WARN: could not register GSD capability %s: %s\n' "$CAP_ID" "$why"
  fi
  return 0
}

# unregister_capability: remove the project-scope registration (uninstall).
unregister_capability() {
  if [ ! -d "$TARGET/$CAP_STAGED_REL" ]; then
    printf '= capability %s (not registered)\n' "$CAP_ID"
    return 0
  fi
  resolve_gsd_tools
  if [ -z "$GSD_TOOLS" ]; then
    printf 'WARN: GSD gsd-tools.cjs not found; remove the capability by hand: delete %s and the %s entry in %s.\n' "$CAP_STAGED_REL" "$CAP_ID" "$LEDGER_REL"
    return 0
  fi
  if [ "$DRY" -eq 1 ]; then
    printf '%swould run: node %s capability remove %s --scope project --project-dir %s\n' "$DRY_PREFIX" "$GSD_TOOLS" "$CAP_ID" "$TARGET"
    return 0
  fi
  local out="" rc=0 errf="" err=""
  errf="$(mktemp "${TMPDIR:-/tmp}/gsd-sd-cap.XXXXXX")"
  out="$( cd "$TARGET" && node "$GSD_TOOLS" capability remove "$CAP_ID" --scope project --project-dir "$TARGET" --pick status 2>"$errf" )" || rc=$?
  err="$(cat "$errf" 2>/dev/null || true)"
  rm -f "$errf"
  out="$(printf '%s' "$out" | tr -d '[:space:]')"
  if [ "$rc" -eq 0 ] && [ "$out" = "removed" ]; then
    printf -- '- capability %s (registration removed)\n' "$CAP_ID"
  elif [ "$rc" -ne 0 ] && printf '%s' "$err" | grep -qF 'not installed'; then
    printf '= capability %s (not registered)\n' "$CAP_ID"
  else
    local why
    why="$(first_line "$err")"
    [ -n "$why" ] || why="$out"
    printf 'WARN: could not remove GSD capability %s (%s). Clean up by hand: delete %s and the %s entry in %s.\n' "$CAP_ID" "$why" "$CAP_STAGED_REL" "$CAP_ID" "$LEDGER_REL"
  fi
  return 0
}

# ---------------------------------------------------------------------------
# register-only
# ---------------------------------------------------------------------------

if [ "$REGISTER_ONLY" -eq 1 ]; then
  if [ ! -f "$TARGET/$SKILLS_REL/gsd-ui-stitch-phase/SKILL.md" ] && [ ! -f "${HOME:-/nonexistent}/$SKILLS_REL/gsd-ui-stitch-phase/SKILL.md" ]; then
    printf 'WARN: skill gsd-ui-stitch-phase is not installed in %s/%s or in $HOME; the hook would dispatch a missing skill. Registering anyway; run install.sh without --register-only to install the skills.\n' "$TARGET" "$SKILLS_REL"
  fi
  register_capability
  print_reregister_hint
  if [ "$DRY" -eq 1 ]; then
    printf '[dry-run] 未做任何改动。\n'
  fi
  exit 0
fi

# ---------------------------------------------------------------------------
# uninstall
# ---------------------------------------------------------------------------

if [ "$UNINSTALL" -eq 1 ]; then
  unregister_capability

  for name in $SKILL_NAMES; do
    p="$TARGET/$SKILLS_REL/$name"
    if [ -d "$p" ]; then
      [ "$DRY" -eq 1 ] || rm -rf "$p"
      act "- $SKILLS_REL/$name"
    else
      act "= $SKILLS_REL/$name (not installed)"
    fi
  done

  # shellcheck disable=SC2086
  node -e "$CLAUDE_JS" uninstall "$DRY" "$DRY_PREFIX" "$PACK_DIR/templates/CLAUDE-section.md" "$TARGET" $CLAUDE_CANDIDATES_REL

  if [ -f "$TARGET/$VERSION_REL" ]; then
    [ "$DRY" -eq 1 ] || rm -f "$TARGET/$VERSION_REL"
    act "- $VERSION_REL"
  else
    act "= $VERSION_REL (not present)"
  fi

  printf 'NOTE: .planning/design and workflow.ui_phase in .planning/config.json were left as-is; %s is kept (GSD leaves the file with an empty entries object).\n' "$LEDGER_REL"
  exit 0
fi

# ---------------------------------------------------------------------------
# install
# ---------------------------------------------------------------------------

# GSD check (warning only).
if [ ! -d "$TARGET/.claude/gsd-core" ] && [ ! -d "${HOME:-/nonexistent}/.claude/gsd-core" ] && ! command -v gsd_run >/dev/null 2>&1; then
  printf 'WARN: GSD was not found (no .claude/gsd-core in the project or in $HOME, no gsd_run on PATH). The skills need GSD at run time; installing anyway.\n'
fi

# Conflict pre-scan: nothing is written before this passes.
CONFLICTS=0
while IFS= read -r src; do
  rel="${src#"$PACK_DIR"/skills/}"
  dst="$TARGET/$SKILLS_REL/$rel"
  if [ -f "$dst" ] && ! cmp -s "$src" "$dst"; then
    local_n=$( (diff "$dst" "$src" 2>/dev/null || true) | grep -c '^<' || true)
    pack_n=$( (diff "$dst" "$src" 2>/dev/null || true) | grep -c '^>' || true)
    printf 'CONFLICT: %s/%s (local +%s / pack +%s lines)\n' "$SKILLS_REL" "$rel" "$local_n" "$pack_n"
    CONFLICTS=$((CONFLICTS + 1))
  fi
done < <(find "$PACK_DIR/skills" -type f | LC_ALL=C sort)

if [ "$CONFLICTS" -gt 0 ] && [ "$FORCE" -eq 0 ]; then
  printf 'Refusing to overwrite %s locally modified skill file(s). Rerun with --force to replace them (local edits in those files will be lost).\n' "$CONFLICTS"
  exit 3
fi

# Installed files that are no longer part of the pack.
for name in $SKILL_NAMES; do
  d="$TARGET/$SKILLS_REL/$name"
  [ -d "$d" ] || continue
  while IFS= read -r have; do
    rel="${have#"$TARGET"/"$SKILLS_REL"/}"
    if [ ! -f "$PACK_DIR/skills/$rel" ]; then
      printf 'WARN: %s/%s is not part of this pack version; left in place.\n' "$SKILLS_REL" "$rel"
    fi
  done < <(find "$d" -type f | LC_ALL=C sort)
done

# Copy skills.
SAME=0
while IFS= read -r src; do
  rel="${src#"$PACK_DIR"/skills/}"
  dst="$TARGET/$SKILLS_REL/$rel"
  if [ ! -e "$dst" ]; then
    if [ "$DRY" -eq 0 ]; then
      mkdir -p "$(dirname "$dst")"
      cp -p "$src" "$dst"
    fi
    act "+ $SKILLS_REL/$rel"
  elif cmp -s "$src" "$dst"; then
    SAME=$((SAME + 1))
  else
    [ "$DRY" -eq 1 ] || cp -p "$src" "$dst"
    act "~ $SKILLS_REL/$rel (overwritten, --force)"
  fi
done < <(find "$PACK_DIR/skills" -type f | LC_ALL=C sort)
if [ "$SAME" -gt 0 ]; then
  act "= $SAME skill file(s) unchanged"
fi

# design-config.json: only when absent.
if [ -f "$TARGET/$DESIGN_CONFIG_REL" ]; then
  act "= $DESIGN_CONFIG_REL (kept, never overwritten)"
else
  if [ "$DRY" -eq 0 ]; then
    mkdir -p "$TARGET/.planning/design"
    cp "$PACK_DIR/templates/design-config.json" "$TARGET/$DESIGN_CONFIG_REL"
  fi
  act "+ $DESIGN_CONFIG_REL"
fi

# CLAUDE.md block.
# shellcheck disable=SC2086
node -e "$CLAUDE_JS" install "$DRY" "$DRY_PREFIX" "$PACK_DIR/templates/CLAUDE-section.md" "$TARGET" $CLAUDE_CANDIDATES_REL

# .planning/config.json: workflow.ui_phase = true.
if [ -f "$TARGET/.planning/config.json" ]; then
  node -e "$PLANNING_JS" "$DRY" "$DRY_PREFIX" "$TARGET/.planning/config.json"
else
  printf 'WARN: .planning/config.json not found. After /gsd-new-project set workflow.ui_phase=true in it (or rerun this script).\n'
fi

# Version file.
if [ -f "$TARGET/$VERSION_REL" ] && [ "$(tr -d '[:space:]' < "$TARGET/$VERSION_REL")" = "$PACK_VERSION" ]; then
  act "= $VERSION_REL ($PACK_VERSION)"
else
  if [ "$DRY" -eq 0 ]; then
    mkdir -p "$TARGET/$SKILLS_REL"
    printf '%s\n' "$PACK_VERSION" > "$TARGET/$VERSION_REL"
  fi
  act "+ $VERSION_REL ($PACK_VERSION)"
fi

# GSD capability.
register_capability

if [ "$DRY" -eq 1 ]; then
  printf '[dry-run] 未做任何改动。\n'
  exit 0
fi

case "$RESULT" in
  registered|active)
    STEP5="  5. GSD 能力 ui-stitch 已注册：/gsd-autonomous 和 /gsd-plan-phase --auto 现在会在前端阶段的 gsd-ui-phase 之后自动运行 gsd-ui-stitch-phase。
     请把两个登记文件都提交进仓库（.gsd-capabilities.json 是 capability remove 所需的登记册，其 source 字段记录本机的 pack 路径）：
       git add .gsd-capabilities.json
       git add -f .gsd/capabilities/ui-stitch/capability.json
     第二条必须带 -f：GSD 把运行时文件放在 .gsd/ 里，并写入内容为 * 的 .gsd/.gitignore，普通的 git add 会悄悄跳过 capability.json。不要去改那个 .gitignore，它归 GSD 管。
     提交之后，新克隆只需运行下面的重新注册命令，工作区仍然干净：重新注册只改动易变字段（updatedAt、source）时，安装器会把已提交的登记册还原回去。
     授权记录（consent）保存在 \${GSD_HOME:-\$HOME}/.gsd/consent.json，按机器、按项目绝对路径记录，不要提交。换新机器、云端会话或移动项目目录后，需要再运行一次下面的重新注册命令。
     关闭：把 workflow.ui_stitch 设为 false。"
    ;;
  *)
    STEP5="  5. GSD 能力 ui-stitch 未注册，/gsd-autonomous 暂不会自动运行 gsd-ui-stitch-phase（原因见上方输出；--no-autonomous 是有意跳过）。
     要启用时，运行下面的重新注册命令。"
    ;;
esac

cat <<EOF

安装完成（版本 $PACK_VERSION）。下一步：
  1. 编辑 .planning/design/design-config.json，至少填写 product_name、product_pitch、audience、ui_language。
  2. 可选：连接 Google Stitch MCP（renderer 设为 html 时不需要，也能完整使用）。
  3. 开始全局设计：/gsd-ui-design-pick（挑选模板），或 /gsd-ui-stitch-phase --design-only --design <你的 DESIGN.md>。
  4. 之后每个前端阶段：discuss-phase -> /gsd-ui-stitch-phase {N} -> plan-phase（自动模式下这一步由 plan:pre 钩子自动运行）。
$STEP5

EOF
print_reregister_hint
if [ "$RESULT" = "skipped" ]; then
  printf '已用 --no-autonomous 跳过注册。要移除已有注册：install.sh <目录> --uninstall，或 node <gsd-tools> capability remove ui-stitch --scope project。\n'
fi
