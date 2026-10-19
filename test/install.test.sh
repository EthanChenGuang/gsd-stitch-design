#!/usr/bin/env bash
# End-to-end test for the gsd-stitch-design pack.
# Usage: bash tools/gsd-stitch-design/test/install.test.sh
set -euo pipefail

PACK_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
INSTALL="$PACK_DIR/install.sh"
CONTRAST="$PACK_DIR/skills/gsd-ui-stitch-phase/scripts/contrast.cjs"
SHOOT="$PACK_DIR/skills/gsd-ui-stitch-phase/scripts/shoot.cjs"
CATALOG="$PACK_DIR/skills/gsd-ui-design-pick/scripts/design-catalog.cjs"
START_MARK='<!-- gsd-stitch-design:start -->'
END_MARK='<!-- gsd-stitch-design:end -->'

TMP="$(mktemp -d "${TMPDIR:-/tmp}/gsd-sd-test.XXXXXX")"
cleanup() { rm -rf "$TMP"; }
trap cleanup EXIT
mkdir -p "$TMP/home"
export HOME="$TMP/home"

fail() {
  printf 'FAIL: %s\n' "$*" >&2
  exit 1
}
ok() {
  printf 'ok - %s\n' "$*"
}

# Run a command, capture combined output in OUT and exit code in RC (works under set -e).
run() {
  RC=0
  OUT="$("$@" 2>&1)" || RC=$?
}

hash_file() {
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum "$1" | cut -d' ' -f1
  else
    shasum -a 256 "$1" | cut -d' ' -f1
  fi
}

# snapshot <dir>: sorted listing of all paths plus hashes of all files.
snapshot() {
  (
    cd "$1"
    find . | LC_ALL=C sort
    find . -type f | LC_ALL=C sort | while IFS= read -r f; do
      printf '%s  %s\n' "$(hash_file "$f")" "$f"
    done
  )
}

count_in() { # count_in <needle> <file>
  local n
  n=$(grep -cF -- "$1" "$2" || true)
  printf '%s' "$n"
}

assert_eq() { # assert_eq <expected> <actual> <message>
  [ "$1" = "$2" ] || fail "$3 (expected '$1', got '$2')"
}

assert_rc() { # assert_rc <expected> <message>
  [ "$RC" -eq "$1" ] || fail "$2 (exit $RC, expected $1). Output: $OUT"
}

# ---------------------------------------------------------------------------
# static
# ---------------------------------------------------------------------------
bash -n "$INSTALL" || fail "bash -n install.sh"
ok "static: bash -n install.sh"

CJS_COUNT=0
while IFS= read -r f; do
  node --check "$f" || fail "node --check $f"
  CJS_COUNT=$((CJS_COUNT + 1))
done < <(find "$PACK_DIR" -name '*.cjs' -type f | LC_ALL=C sort)
ok "static: node --check on $CJS_COUNT .cjs file(s)"

node -e 'JSON.parse(require("fs").readFileSync(process.argv[1], "utf8"))' "$PACK_DIR/templates/design-config.json" \
  || fail "design-config.json template is not valid JSON"
ok "static: design-config.json template parses"

# ---------------------------------------------------------------------------
# contrast
# ---------------------------------------------------------------------------
run node "$CONTRAST" "#1A1A1A" "#FFFFFF"
assert_rc 0 "contrast 1A1A1A/FFFFFF"
case "$OUT" in 17.40:1*) ;; *) fail "contrast 1A1A1A/FFFFFF: $OUT" ;; esac
run node "$CONTRAST" 777 fff
assert_rc 0 "contrast 777/fff"
case "$OUT" in *"4.48:1"*"AA:fail"*"AA-large:pass"*) ;; *) fail "contrast 777/fff: $OUT" ;; esac
run node "$CONTRAST" "#767676" "#fff"
case "$OUT" in *"4.54:1"*"AA:pass"*) ;; *) fail "contrast 767676/fff: $OUT" ;; esac
run node "$CONTRAST" "#FFF" "#000"
case "$OUT" in 21.00:1*) ;; *) fail "contrast FFF/000: $OUT" ;; esac
run node "$CONTRAST" "#GGG" "#fff"
assert_rc 2 "contrast bad hex"
ok "contrast: ground-truth ratios and bad-hex exit 2"

# ---------------------------------------------------------------------------
# shoot (guarded)
# ---------------------------------------------------------------------------
if [ ! -f "$SHOOT" ]; then
  printf 'skip - shoot (script not present)\n'
else
  run node "$SHOOT" --check
  if [ "$RC" -eq 0 ]; then
    mkdir -p "$TMP/shoot"
    printf '<!doctype html><html><body style="margin:0;background:#3366ff"><p style="color:#fff">x</p></body></html>\n' > "$TMP/shoot/fixture.html"
    run node "$SHOOT" --width 200 --height 100 --scale 2 "$TMP/shoot/fixture.html"
    assert_rc 0 "shoot render"
    [ -f "$TMP/shoot/fixture.png" ] || fail "shoot did not write fixture.png"
    DIM=$(node -e 'const b=require("fs").readFileSync(process.argv[1]);console.log(b.readUInt32BE(16)+"x"+b.readUInt32BE(20))' "$TMP/shoot/fixture.png")
    assert_eq "400x200" "$DIM" "shoot PNG size"
    ok "shoot: rendered 400x200"
  else
    case "$OUT" in
      *"npx playwright install chromium"*) ok "shoot: missing-playwright hint" ;;
      *) fail "shoot --check failed without the install hint: $OUT" ;;
    esac
  fi
fi

# ---------------------------------------------------------------------------
# design-catalog (guarded)
# ---------------------------------------------------------------------------
if [ ! -f "$CATALOG" ]; then
  printf 'skip - design-catalog (script not present)\n'
else
  mkdir -p "$TMP/catalog/demo"
  cat > "$TMP/catalog/demo/DESIGN.md" <<'EOF'
---
name: Demo
description: A demo design
colors:
  primary: "#3366FF"
  canvas: "#FFFFFF"
  success: "#1E8E3E"
typography:
  body:
    fontFamily: Inter
---

## Overview

Demo text.
EOF
  run node "$CATALOG" "$TMP/catalog"
  assert_rc 0 "design-catalog run"
  printf '%s' "$OUT" > "$TMP/catalog.json"
  node -e '
    const a = JSON.parse(require("fs").readFileSync(process.argv[1], "utf8"));
    const bad = [];
    if (a.length !== 1) bad.push("length " + a.length);
    const e = a[0] || {};
    if (e.id !== "demo") bad.push("id " + e.id);
    if (e.primary !== "#3366FF") bad.push("primary " + e.primary);
    if (e.darkCanvas !== false) bad.push("darkCanvas " + e.darkCanvas);
    if (e.colorCount !== 3) bad.push("colorCount " + e.colorCount);
    if (e.hasSemantic !== true) bad.push("hasSemantic " + e.hasSemantic);
    if (!(e.fonts || []).includes("Inter")) bad.push("fonts " + JSON.stringify(e.fonts));
    if (bad.length) { console.error(bad.join("; ")); process.exit(1); }
  ' "$TMP/catalog.json" || fail "design-catalog output mismatch"
  run node "$CATALOG"
  assert_rc 2 "design-catalog no-arg"
  ok "design-catalog"
fi

# ---------------------------------------------------------------------------
# usage
# ---------------------------------------------------------------------------
run bash "$INSTALL"
assert_rc 2 "install.sh with no args"
run bash "$INSTALL" "$TMP/does-not-exist"
[ "$RC" -ne 0 ] || fail "install.sh with a nonexistent target must fail"
ok "usage: no args -> 2, nonexistent target -> $RC"

# ---------------------------------------------------------------------------
# scenario A: project with CLAUDE.md and .planning/config.json
# ---------------------------------------------------------------------------
A="$TMP/fake project"
mkdir -p "$A/.claude" "$A/.planning"
printf '{"workflow":{"ui_phase":false,"research":true},"commit_docs":true}\n' > "$A/.planning/config.json"
printf '# Fixture project\n\nExisting rule line.\n' > "$A/.claude/CLAUDE.md"
cp "$A/.claude/CLAUDE.md" "$TMP/claude-fixture.md"

# A1: dry-run on a fresh project changes nothing
SNAP_BEFORE="$(snapshot "$A")"
run bash "$INSTALL" "$A" --dry-run
assert_rc 0 "A1 dry-run fresh"
case "$OUT" in *"[dry-run]"*) ;; *) fail "A1 dry-run output lacks [dry-run]: $OUT" ;; esac
assert_eq "$SNAP_BEFORE" "$(snapshot "$A")" "A1 dry-run changed the project"
ok "A1: dry-run on a fresh project changes nothing"

# A2: real install
run bash "$INSTALL" "$A"
assert_rc 0 "A2 install"
SKILL_FILES=0
while IFS= read -r src; do
  rel="${src#"$PACK_DIR"/skills/}"
  cmp -s "$src" "$A/.claude/skills/$rel" || fail "A2 skill file differs or is missing: $rel"
  SKILL_FILES=$((SKILL_FILES + 1))
done < <(find "$PACK_DIR/skills" -type f | LC_ALL=C sort)
[ "$SKILL_FILES" -gt 0 ] || fail "A2 pack has no skill files"
cmp -s "$PACK_DIR/templates/design-config.json" "$A/.planning/design/design-config.json" || fail "A2 design-config.json differs from template"
assert_eq "$(tr -d '[:space:]' < "$PACK_DIR/VERSION")" "$(tr -d '[:space:]' < "$A/.claude/skills/.gsd-stitch-design-version")" "A2 version file"
assert_eq "1" "$(count_in "$START_MARK" "$A/.claude/CLAUDE.md")" "A2 start marker count"
assert_eq "1" "$(count_in "$END_MARK" "$A/.claude/CLAUDE.md")" "A2 end marker count"
head -c "$(wc -c < "$TMP/claude-fixture.md")" "$A/.claude/CLAUDE.md" | cmp -s - "$TMP/claude-fixture.md" || fail "A2 original CLAUDE.md text changed"
[ ! -f "$A/CLAUDE.md" ] || fail "A2 created a root CLAUDE.md"
node -e '
  const c = JSON.parse(require("fs").readFileSync(process.argv[1], "utf8"));
  if (c.workflow.ui_phase !== true || c.workflow.research !== true || c.commit_docs !== true) process.exit(1);
' "$A/.planning/config.json" || fail "A2 .planning/config.json not updated correctly"
case "$OUT" in *"WARN: GSD was not found"*) ;; *) fail "A2 expected GSD warning with empty HOME: $OUT" ;; esac
ok "A2: install copies $SKILL_FILES skill files, config, one marker block, ui_phase=true, version"

# A3: user edits design-config.json, reinstall is idempotent
node -e '
  const fs = require("fs");
  const c = JSON.parse(fs.readFileSync(process.argv[1], "utf8"));
  c.product_name = "Demo Product";
  fs.writeFileSync(process.argv[1], JSON.stringify(c, null, 2) + "\n");
' "$A/.planning/design/design-config.json"
H_CLAUDE="$(hash_file "$A/.claude/CLAUDE.md")"
H_CFG="$(hash_file "$A/.planning/config.json")"
H_DC="$(hash_file "$A/.planning/design/design-config.json")"
run bash "$INSTALL" "$A"
assert_rc 0 "A3 reinstall"
assert_eq "$H_CLAUDE" "$(hash_file "$A/.claude/CLAUDE.md")" "A3 CLAUDE.md changed on reinstall"
assert_eq "$H_CFG" "$(hash_file "$A/.planning/config.json")" "A3 .planning/config.json changed on reinstall"
assert_eq "$H_DC" "$(hash_file "$A/.planning/design/design-config.json")" "A3 design-config.json overwritten"
assert_eq "1" "$(count_in "$START_MARK" "$A/.claude/CLAUDE.md")" "A3 start marker count"
ok "A3: reinstall is idempotent and keeps the edited design-config.json"

# A4: dry-run on an installed project
SNAP_BEFORE="$(snapshot "$A")"
run bash "$INSTALL" "$A" --dry-run
assert_rc 0 "A4 dry-run installed"
case "$OUT" in *"[dry-run]"*) ;; *) fail "A4 dry-run output lacks [dry-run]" ;; esac
assert_eq "$SNAP_BEFORE" "$(snapshot "$A")" "A4 dry-run changed the project"
ok "A4: dry-run on an installed project changes nothing"

# A5: conflict protection
CONTRAST_INSTALLED="$A/.claude/skills/gsd-ui-stitch-phase/scripts/contrast.cjs"
printf '// local edit\n' >> "$CONTRAST_INSTALLED"
run bash "$INSTALL" "$A"
assert_rc 3 "A5 conflict without --force"
case "$OUT" in *"CONFLICT:"*) ;; *) fail "A5 missing CONFLICT line: $OUT" ;; esac
grep -qF '// local edit' "$CONTRAST_INSTALLED" || fail "A5 local edit was lost without --force"
run bash "$INSTALL" "$A" --force
assert_rc 0 "A5 --force"
cmp -s "$CONTRAST" "$CONTRAST_INSTALLED" || fail "A5 --force did not restore the pack file"
ok "A5: edited skill file -> exit 3 + CONFLICT; --force restores it"

# A6: uninstall (dry-run first)
SNAP_BEFORE="$(snapshot "$A")"
run bash "$INSTALL" "$A" --uninstall --dry-run
assert_rc 0 "A6 uninstall dry-run"
case "$OUT" in *"[dry-run]"*) ;; *) fail "A6 dry-run output lacks [dry-run]" ;; esac
assert_eq "$SNAP_BEFORE" "$(snapshot "$A")" "A6 uninstall dry-run changed the project"
run bash "$INSTALL" "$A" --uninstall
assert_rc 0 "A6 uninstall"
[ ! -e "$A/.claude/skills/gsd-ui-stitch-phase" ] || fail "A6 gsd-ui-stitch-phase still present"
[ ! -e "$A/.claude/skills/gsd-ui-design-pick" ] || fail "A6 gsd-ui-design-pick still present"
[ ! -e "$A/.claude/skills/.gsd-stitch-design-version" ] || fail "A6 version file still present"
assert_eq "0" "$(count_in "$START_MARK" "$A/.claude/CLAUDE.md")" "A6 start marker left"
assert_eq "0" "$(count_in "$END_MARK" "$A/.claude/CLAUDE.md")" "A6 end marker left"
cmp -s "$TMP/claude-fixture.md" "$A/.claude/CLAUDE.md" || fail "A6 CLAUDE.md is not byte-identical to the fixture"
[ -f "$A/.planning/design/design-config.json" ] || fail "A6 .planning/design/design-config.json was removed"
grep -qF 'Demo Product' "$A/.planning/design/design-config.json" || fail "A6 design-config.json edit was lost"
ok "A6: uninstall removes skills, block, version file; CLAUDE.md byte-identical; .planning/design kept"

# ---------------------------------------------------------------------------
# scenario B: empty project (no CLAUDE.md, no .planning)
# ---------------------------------------------------------------------------
B="$TMP/empty"
mkdir -p "$B"
run bash "$INSTALL" "$B"
assert_rc 0 "B install"
[ -f "$B/.claude/CLAUDE.md" ] || fail "B .claude/CLAUDE.md not created"
assert_eq "1" "$(count_in "$START_MARK" "$B/.claude/CLAUDE.md")" "B start marker count"
assert_eq "1" "$(count_in "$END_MARK" "$B/.claude/CLAUDE.md")" "B end marker count"
case "$OUT" in *"WARN:"*".planning/config.json"*) ;; *) fail "B missing .planning/config.json warning: $OUT" ;; esac
run bash "$INSTALL" "$B" --uninstall
assert_rc 0 "B uninstall"
[ ! -e "$B/.claude/CLAUDE.md" ] || fail "B .claude/CLAUDE.md should be deleted when empty"
ok "B: empty project -> .claude/CLAUDE.md created with one block + WARN; uninstall deletes it"

# ---------------------------------------------------------------------------
# scenario C: root CLAUDE.md only
# ---------------------------------------------------------------------------
C="$TMP/rootonly"
mkdir -p "$C"
printf '# Root file\n' > "$C/CLAUDE.md"
cp "$C/CLAUDE.md" "$TMP/root-fixture.md"
run bash "$INSTALL" "$C"
assert_rc 0 "C install"
assert_eq "1" "$(count_in "$START_MARK" "$C/CLAUDE.md")" "C root block count"
[ ! -e "$C/.claude/CLAUDE.md" ] || fail "C created .claude/CLAUDE.md although a root CLAUDE.md exists"
run bash "$INSTALL" "$C" --uninstall
assert_rc 0 "C uninstall"
cmp -s "$TMP/root-fixture.md" "$C/CLAUDE.md" || fail "C root CLAUDE.md not restored byte-for-byte"
ok "C: root CLAUDE.md gets the block, no .claude/CLAUDE.md is created, uninstall restores it"

printf 'ALL TESTS PASSED\n'
