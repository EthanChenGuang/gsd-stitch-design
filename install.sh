#!/usr/bin/env bash
# gsd-stitch-design installer.
# Installs the gsd-ui-stitch-phase and gsd-ui-design-pick skills into another GSD project.
# Usage: install.sh <target-project-dir> [--dry-run] [--force] [--uninstall]
set -euo pipefail

USAGE="Usage: install.sh <target-project-dir> [--dry-run] [--force] [--uninstall]

  --dry-run    print what would happen, change nothing
  --force      overwrite installed skill files that differ from the pack
  --uninstall  remove the two skills, the CLAUDE.md block and the version file
               (.planning/design and workflow.ui_phase are left as-is)
  -h, --help   show this help

Exit codes: 0 ok, 1 error, 2 usage error, 3 refused because of conflicts"

DRY=0
FORCE=0
UNINSTALL=0
TARGET_ARG=""

while [ $# -gt 0 ]; do
  case "$1" in
    --dry-run) DRY=1 ;;
    --force) FORCE=1 ;;
    --uninstall) UNINSTALL=1 ;;
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

# ---------------------------------------------------------------------------
# uninstall
# ---------------------------------------------------------------------------

if [ "$UNINSTALL" -eq 1 ]; then
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

  printf 'NOTE: .planning/design and workflow.ui_phase in .planning/config.json were left as-is.\n'
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

if [ "$DRY" -eq 1 ]; then
  printf '[dry-run] 未做任何改动。\n'
  exit 0
fi

cat <<EOF

安装完成（版本 $PACK_VERSION）。下一步：
  1. 编辑 .planning/design/design-config.json，至少填写 product_name、product_pitch、audience、ui_language。
  2. 可选：连接 Google Stitch MCP（renderer 设为 html 时不需要，也能完整使用）。
  3. 开始全局设计：/gsd-ui-design-pick（挑选模板），或 /gsd-ui-stitch-phase --design-only --design <你的 DESIGN.md>。
  4. 之后每个前端阶段：discuss-phase -> /gsd-ui-stitch-phase {N} -> plan-phase。
EOF
