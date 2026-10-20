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

node -e '
  const fs = require("fs");
  const [capFile, verFile] = process.argv.slice(1);
  const c = JSON.parse(fs.readFileSync(capFile, "utf8"));
  const v = fs.readFileSync(verFile, "utf8").trim();
  const bad = [];
  if (c.id !== "ui-stitch") bad.push("id " + c.id);
  const st = (c.steps || [])[0] || {};
  if (!st.ref || st.ref.skill !== "ui-stitch-phase") bad.push("steps[0].ref.skill");
  if ((st.produces || []).includes("UI-SPEC.md")) bad.push("step must not produce UI-SPEC.md");
  if (c.version !== v) bad.push("version " + c.version + " != VERSION " + v);
  if (bad.length) { console.error(bad.join("; ")); process.exit(1); }
' "$PACK_DIR/capability/ui-stitch/capability.json" "$PACK_DIR/VERSION" \
  || fail "capability.json check failed"
ok "static: capability.json parses, version matches VERSION"

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
run bash "$INSTALL" "$TMP" --register-only --uninstall
assert_rc 2 "--register-only with --uninstall"
run bash "$INSTALL" "$TMP" --register-only --no-autonomous
assert_rc 2 "--register-only with --no-autonomous"
ok "usage: --register-only combined with --uninstall or --no-autonomous -> 2"

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

# ---------------------------------------------------------------------------
# scenario F: --register-only without GSD anywhere
# ---------------------------------------------------------------------------
F="$TMP/nogsd"
mkdir -p "$F/.planning"
printf '{"workflow":{}}\n' > "$F/.planning/config.json"
SNAP_BEFORE="$(snapshot "$F")"
run bash "$INSTALL" "$F" --register-only
assert_rc 0 "F register-only without GSD"
case "$OUT" in *"WARN"*) ;; *) fail "F expected a WARN: $OUT" ;; esac
case "$OUT" in *"--register-only"*) ;; *) fail "F expected the re-register line: $OUT" ;; esac
assert_eq "$SNAP_BEFORE" "$(snapshot "$F")" "F --register-only changed the project"
ok "F: --register-only without GSD warns, exits 0, changes nothing"

# ---------------------------------------------------------------------------
# scenario D: GSD capability integration against the real gsd-tools (guarded)
# ---------------------------------------------------------------------------
GSD_CORE_SRC="${GSD_CORE_SRC:-$PACK_DIR/../../.claude/gsd-core}"
if [ ! -f "$GSD_CORE_SRC/bin/gsd-tools.cjs" ]; then
  printf 'skip - capability integration (no GSD at %s; set GSD_CORE_SRC)\n' "$GSD_CORE_SRC"
else
  D="$TMP/gsd project"
  mkdir -p "$D/.claude" "$D/.planning"
  printf '{"workflow":{"ui_phase":false}}\n' > "$D/.planning/config.json"
  printf '# Fixture project\n' > "$D/.claude/CLAUDE.md"
  cp -R "$GSD_CORE_SRC" "$D/.claude/gsd-core"
  if [ -d "$(dirname "$GSD_CORE_SRC")/scripts" ]; then
    cp -R "$(dirname "$GSD_CORE_SRC")/scripts" "$D/.claude/scripts"
  fi
  mkdir -p "$TMP/gsdhome-1"
  export GSD_HOME="$TMP/gsdhome-1"
  D_STAGED="$D/.gsd/capabilities/ui-stitch"
  D_LEDGER="$D/.gsd-capabilities.json"

  # hooks_state <proj>: active | absent | partial:... (from the plan:pre hooks GSD renders)
  hooks_state() {
    node "$1/.claude/gsd-core/bin/gsd-tools.cjs" loop render-hooks plan:pre --raw --project-dir "$1" 2>/dev/null \
      | node -e '
        let d = "";
        process.stdin.on("data", (c) => (d += c)).on("end", () => {
          let h;
          try { h = JSON.parse(d).activeHooks; } catch (e) { console.log("unparsable"); return; }
          const iUi = h.findIndex((e) => e.kind === "step" && e.capId === "ui");
          const iSt = h.findIndex((e) => e.kind === "step" && e.capId === "ui-stitch" && e.ref && e.ref.skill === "ui-stitch-phase");
          const contrib = h.some((e) => e.kind === "contribution" && e.capId === "ui-stitch" && e.into === "planner");
          if (iUi >= 0 && iSt > iUi && contrib) console.log("active");
          else if (!h.some((e) => e.capId === "ui-stitch")) console.log("absent");
          else console.log("partial:ui=" + iUi + ",stitch=" + iSt + ",contrib=" + contrib);
        });
      ' || true
  }
  assert_hooks() { # assert_hooks <expected> <message>
    local got
    got="$(hooks_state "$D")"
    [ -n "$got" ] || fail "$2 (hooks_state printed nothing)"
    assert_eq "$1" "$got" "$2"
  }

  # D1: dry-run changes nothing and prints the registration command
  run bash "$INSTALL" "$D" --dry-run
  assert_rc 0 "D1 dry-run"
  case "$OUT" in *"[dry-run]"*"capability install"*) ;; *) fail "D1 dry-run output lacks the capability install command: $OUT" ;; esac
  [ ! -e "$D_STAGED" ] || fail "D1 dry-run created $D_STAGED"
  [ ! -e "$D_LEDGER" ] || fail "D1 dry-run created $D_LEDGER"
  ok "D1: dry-run prints the capability install command and writes nothing"

  # D2: --no-autonomous installs skills but registers nothing
  run bash "$INSTALL" "$D" --no-autonomous
  assert_rc 0 "D2 --no-autonomous"
  [ -f "$D/.claude/skills/gsd-ui-stitch-phase/SKILL.md" ] || fail "D2 skills were not installed"
  [ ! -e "$D_STAGED" ] || fail "D2 registered the capability"
  case "$OUT" in *"--no-autonomous"*) ;; *) fail "D2 output does not mention --no-autonomous: $OUT" ;; esac
  assert_hooks absent "D2 hooks"
  ok "D2: --no-autonomous installs skills and registers nothing"

  # D3: default install registers the capability
  run bash "$INSTALL" "$D"
  assert_rc 0 "D3 install"
  cmp -s "$PACK_DIR/capability/ui-stitch/capability.json" "$D_STAGED/capability.json" || fail "D3 staged capability.json differs from the pack"
  assert_hooks active "D3 hooks (ui-stitch step after ui step + planner contribution)"
  case "$OUT" in *"WARN: could not register"*) fail "D3 registration warning: $OUT" ;; esac
  case "$OUT" in *"--register-only"*) ;; *) fail "D3 output lacks the re-register line: $OUT" ;; esac
  case "$OUT" in *".gsd-capabilities.json"*) ;; *) fail "D3 output lacks the commit guidance: $OUT" ;; esac
  case "$OUT" in *"git add -f .gsd/capabilities/ui-stitch/capability.json"*) ;; *) fail "D3 output lacks the git add -f guidance: $OUT" ;; esac
  ok "D3: install registers ui-stitch (step after ui, planner contribution)"

  # D4: reinstall is idempotent, no ledger churn
  H_LEDGER="$(hash_file "$D_LEDGER")"
  run bash "$INSTALL" "$D"
  assert_rc 0 "D4 reinstall"
  case "$OUT" in *"WARN: could not register"*) fail "D4 registration warning: $OUT" ;; esac
  case "$OUT" in *"= capability ui-stitch"*) ;; *) fail "D4 expected '= capability ui-stitch': $OUT" ;; esac
  assert_hooks active "D4 hooks"
  assert_eq "$H_LEDGER" "$(hash_file "$D_LEDGER")" "D4 ledger changed on reinstall"
  ok "D4: reinstall exits 0, capability stays active, ledger untouched"

  # D5: fresh GSD_HOME (new machine) -> inactive; --register-only re-activates, touches nothing else
  mkdir -p "$TMP/gsdhome-2"
  export GSD_HOME="$TMP/gsdhome-2"
  assert_hooks absent "D5 hooks with a fresh GSD_HOME"
  H_CLAUDE="$(hash_file "$D/.claude/CLAUDE.md")"
  H_CFG="$(hash_file "$D/.planning/config.json")"
  H_VER="$(hash_file "$D/.claude/skills/.gsd-stitch-design-version")"
  H_SKILL="$(hash_file "$D/.claude/skills/gsd-ui-stitch-phase/SKILL.md")"
  run bash "$INSTALL" "$D" --register-only
  assert_rc 0 "D5 --register-only"
  assert_hooks active "D5 hooks after --register-only"
  case "$OUT" in *".gsd-capabilities.json ("*) fail "D5 non-git target printed a ledger line: $OUT" ;; esac
  assert_eq "$H_CLAUDE" "$(hash_file "$D/.claude/CLAUDE.md")" "D5 CLAUDE.md changed"
  assert_eq "$H_CFG" "$(hash_file "$D/.planning/config.json")" "D5 .planning/config.json changed"
  assert_eq "$H_VER" "$(hash_file "$D/.claude/skills/.gsd-stitch-design-version")" "D5 version file changed"
  assert_eq "$H_SKILL" "$(hash_file "$D/.claude/skills/gsd-ui-stitch-phase/SKILL.md")" "D5 SKILL.md changed"
  ok "D5: fresh GSD_HOME is inactive; --register-only re-activates and touches nothing else"

  # D6: --register-only --dry-run
  H_LEDGER="$(hash_file "$D_LEDGER")"
  run bash "$INSTALL" "$D" --register-only --dry-run
  assert_rc 0 "D6 register-only dry-run"
  case "$OUT" in *"[dry-run]"*"capability install"*) ;; *) fail "D6 output lacks the dry-run command: $OUT" ;; esac
  assert_eq "$H_LEDGER" "$(hash_file "$D_LEDGER")" "D6 dry-run changed the ledger"
  ok "D6: --register-only --dry-run prints the command and changes nothing"

  # D7: invalid combinations
  run bash "$INSTALL" "$D" --register-only --uninstall
  assert_rc 2 "D7 --register-only --uninstall"
  run bash "$INSTALL" "$D" --register-only --no-autonomous
  assert_rc 2 "D7 --register-only --no-autonomous"
  ok "D7: --register-only with --uninstall or --no-autonomous exits 2"

  # D8: uninstall removes the registration; a second uninstall says so
  run bash "$INSTALL" "$D" --uninstall
  assert_rc 0 "D8 uninstall"
  [ ! -e "$D_STAGED" ] || fail "D8 staged capability still present"
  assert_hooks absent "D8 hooks after uninstall"
  [ ! -e "$D/.claude/skills/gsd-ui-stitch-phase" ] || fail "D8 skills still present"
  run bash "$INSTALL" "$D" --uninstall
  assert_rc 0 "D8 second uninstall"
  case "$OUT" in *"not registered"*) ;; *) fail "D8 second uninstall lacks 'not registered': $OUT" ;; esac
  ok "D8: uninstall removes the registration; second uninstall reports 'not registered'"

  # -------------------------------------------------------------------------
  # scenario G: git-tracked ledger in fresh clones
  # -------------------------------------------------------------------------
  if ! command -v git >/dev/null 2>&1; then
    printf 'skip - git ledger scenarios (git not found)\n'
  else
    # gclone <src> <dst> [branch]: clone, then copy in the ignored GSD copy.
    gclone() {
      if [ -n "${3:-}" ]; then
        git clone -q -b "$3" "$1" "$2" 2>/dev/null
      else
        git clone -q "$1" "$2" 2>/dev/null
      fi
      cp -R "$GSD_CORE_SRC" "$2/.claude/gsd-core"
      if [ -d "$(dirname "$GSD_CORE_SRC")/scripts" ]; then
        cp -R "$(dirname "$GSD_CORE_SRC")/scripts" "$2/.claude/scripts"
      fi
    }
    assert_hooks_in() { # assert_hooks_in <proj> <expected> <message>
      local got
      got="$(hooks_state "$1")"
      [ -n "$got" ] || fail "$3 (hooks_state printed nothing)"
      assert_eq "$2" "$got" "$3"
    }

    S="$TMP/git src"
    mkdir -p "$S/.claude" "$S/.planning"
    printf '/.claude/gsd-core/\n/.claude/scripts/\n' > "$S/.gitignore"
    printf '{"workflow":{"ui_phase":true}}\n' > "$S/.planning/config.json"
    printf '# Fixture project\n' > "$S/.claude/CLAUDE.md"
    cp -R "$GSD_CORE_SRC" "$S/.claude/gsd-core"
    if [ -d "$(dirname "$GSD_CORE_SRC")/scripts" ]; then
      cp -R "$(dirname "$GSD_CORE_SRC")/scripts" "$S/.claude/scripts"
    fi
    git -c init.defaultBranch=main init -q "$S"
    git -C "$S" config user.email "test@example.com"
    git -C "$S" config user.name "Test"
    git -C "$S" config commit.gpgsign false
    mkdir -p "$TMP/gsdhome-g1"
    export GSD_HOME="$TMP/gsdhome-g1"
    run bash "$INSTALL" "$S"
    assert_rc 0 "G setup install"
    case "$OUT" in *"WARN: could not register"*) fail "G setup registration warning: $OUT" ;; esac
    # Emulate GSD's dispatch-isolation sentinel writer (only the fixture writes this file).
    printf '*\n' > "$S/.gsd/.gitignore"

    # G0: P1 reproduction
    git -C "$S" add -A
    git -C "$S" check-ignore -q -- .gsd/capabilities/ui-stitch/capability.json || fail "G0 capability.json is not ignored"
    STAGED="$(git -C "$S" diff --cached --name-only)"
    case "$STAGED" in *".gsd-capabilities.json"*) ;; *) fail "G0 plain add did not stage the ledger: $STAGED" ;; esac
    case "$STAGED" in *"ui-stitch/capability.json"*) fail "G0 plain add staged capability.json: $STAGED" ;; esac
    git -C "$S" add -f -- .gsd/capabilities/ui-stitch/capability.json
    git -C "$S" commit -qm fixture
    TRACKED="$(git -C "$S" ls-files)"
    case "$TRACKED" in *".gsd-capabilities.json"*) ;; *) fail "G0 ledger not tracked: $TRACKED" ;; esac
    case "$TRACKED" in *".gsd/capabilities/ui-stitch/capability.json"*) ;; *) fail "G0 capability.json not tracked: $TRACKED" ;; esac
    ok "G0: GSD's .gsd/.gitignore hides capability.json from plain git add; git add -f commits it"

    # G1: fresh clone, both files committed
    K1="$TMP/clone one"
    gclone "$S" "$K1"
    mkdir -p "$TMP/gsdhome-g2"
    export GSD_HOME="$TMP/gsdhome-g2"
    assert_hooks_in "$K1" absent "G1 hooks before registration"
    run bash "$INSTALL" "$K1" --register-only
    assert_rc 0 "G1 --register-only"
    case "$OUT" in *"= .gsd-capabilities.json (only volatile fields changed; restored)"*) ;; *) fail "G1 missing the restored line: $OUT" ;; esac
    assert_hooks_in "$K1" active "G1 hooks after --register-only"
    assert_eq "" "$(git -C "$K1" status --porcelain)" "G1 work tree is not clean"
    [ ! -e "$K1/.gsd/.gitignore" ] || fail "G1 the installer created .gsd/.gitignore"
    ok "G1: fresh clone with both files committed: --register-only activates and leaves the tree clean"

    # G2: same clone, fresh machine, registering from a second pack path
    mkdir -p "$TMP/gsdhome-g3" "$TMP/second place"
    export GSD_HOME="$TMP/gsdhome-g3"
    cp -R "$PACK_DIR" "$TMP/second place/pack copy"
    assert_hooks_in "$K1" absent "G2 hooks before registration"
    run bash "$TMP/second place/pack copy/install.sh" "$K1" --register-only
    assert_rc 0 "G2 --register-only from a second pack path"
    case "$OUT" in *"= .gsd-capabilities.json (only volatile fields changed; restored)"*) ;; *) fail "G2 missing the restored line: $OUT" ;; esac
    assert_hooks_in "$K1" active "G2 hooks"
    assert_eq "" "$(git -C "$K1" status --porcelain)" "G2 work tree is not clean"
    ok "G2: re-registering from a second pack path leaves the tree clean (only updatedAt/source differ)"

    # G3: --register-only --dry-run writes nothing
    mkdir -p "$TMP/gsdhome-g4"
    export GSD_HOME="$TMP/gsdhome-g4"
    G3_STATUS="$(git -C "$K1" status --porcelain)"
    G3_LEDGER="$(hash_file "$K1/.gsd-capabilities.json")"
    G3_LIST="$(find "$K1/.gsd" | LC_ALL=C sort)"
    G3_INDEX="$(hash_file "$K1/.git/index")"
    run bash "$INSTALL" "$K1" --register-only --dry-run
    assert_rc 0 "G3 register-only dry-run"
    case "$OUT" in *"[dry-run]"*"capability install"*) ;; *) fail "G3 output lacks the dry-run command: $OUT" ;; esac
    case "$OUT" in *"would restore .gsd-capabilities.json"*) ;; *) fail "G3 output lacks the would-restore line: $OUT" ;; esac
    assert_eq "$G3_STATUS" "$(git -C "$K1" status --porcelain)" "G3 dry-run changed the status"
    assert_eq "$G3_LEDGER" "$(hash_file "$K1/.gsd-capabilities.json")" "G3 dry-run changed the ledger"
    assert_eq "$G3_LIST" "$(find "$K1/.gsd" | LC_ALL=C sort)" "G3 dry-run changed .gsd"
    assert_eq "$G3_INDEX" "$(hash_file "$K1/.git/index")" "G3 dry-run changed .git/index"
    [ ! -e "$GSD_HOME/.gsd/consent.json" ] || fail "G3 dry-run wrote the consent store"
    assert_hooks_in "$K1" absent "G3 hooks after dry-run"
    ok "G3: --register-only --dry-run only reports; ledger, .gsd, status, index and consent store unchanged"

    # G4: a real change (version bump) is kept, not restored
    mkdir -p "$TMP/gsdhome-g5"
    export GSD_HOME="$TMP/gsdhome-g5"
    cp -R "$PACK_DIR" "$TMP/pack v9"
    printf '9.9.9\n' > "$TMP/pack v9/VERSION"
    node -e '
      const fs = require("fs");
      const f = process.argv[1];
      const c = JSON.parse(fs.readFileSync(f, "utf8"));
      c.version = "9.9.9";
      fs.writeFileSync(f, JSON.stringify(c, null, 2) + "\n");
    ' "$TMP/pack v9/capability/ui-stitch/capability.json"
    run bash "$TMP/pack v9/install.sh" "$K1" --register-only
    assert_rc 0 "G4 --register-only from the 9.9.9 pack"
    case "$OUT" in *"~ .gsd-capabilities.json"*) ;; *) fail "G4 missing the kept (~) ledger line: $OUT" ;; esac
    case "$OUT" in *"restored"*) fail "G4 restored a real change: $OUT" ;; esac
    G4_VER="$(node -e 'console.log(JSON.parse(require("fs").readFileSync(process.argv[1], "utf8")).entries["ui-stitch"].version)' "$K1/.gsd-capabilities.json")"
    assert_eq "9.9.9" "$G4_VER" "G4 ledger version"
    assert_eq " M .gsd-capabilities.json" "$(git -C "$K1" status --porcelain -- .gsd-capabilities.json)" "G4 ledger status"
    git -C "$K1" checkout -q -- .
    run bash "$INSTALL" "$K1" --register-only
    assert_rc 0 "G4 --register-only from the main pack"
    assert_eq "" "$(git -C "$K1" status --porcelain)" "G4 work tree is not clean after returning to the main pack"
    assert_hooks_in "$K1" active "G4 hooks after returning to the main pack"
    ok "G4: a version change is kept (~ line, M status); returning to the main pack is clean and active"

    # G5: uninstall after a restored ledger
    run bash "$INSTALL" "$K1" --uninstall
    assert_rc 0 "G5 uninstall"
    case "$OUT" in *"- capability ui-stitch (registration removed)"*) ;; *) fail "G5 missing the removal line: $OUT" ;; esac
    [ ! -e "$K1/.gsd/capabilities/ui-stitch" ] || fail "G5 staged capability still present"
    assert_hooks_in "$K1" absent "G5 hooks after uninstall"
    G5_ENTRIES="$(node -e 'const e = JSON.parse(require("fs").readFileSync(process.argv[1], "utf8")).entries; console.log(JSON.stringify(e))' "$K1/.gsd-capabilities.json")"
    assert_eq "{}" "$G5_ENTRIES" "G5 ledger entries"
    ok "G5: --uninstall after a restored ledger removes the registration and empties entries"

    # G6: ledger-only and nothing-committed clones (D-1 cases A and B)
    git -C "$S" checkout -q -b case-a
    git -C "$S" rm -q --cached -- .gsd/capabilities/ui-stitch/capability.json
    git -C "$S" commit -qm "case a: ledger only"
    gclone "$S" "$TMP/clone a" case-a
    mkdir -p "$TMP/gsdhome-g6"
    export GSD_HOME="$TMP/gsdhome-g6"
    assert_hooks_in "$TMP/clone a" absent "G6a hooks before registration"
    run bash "$INSTALL" "$TMP/clone a" --register-only
    assert_rc 0 "G6a --register-only"
    assert_hooks_in "$TMP/clone a" active "G6a hooks"
    G6A_STATUS="$(git -C "$TMP/clone a" status --porcelain)"
    printf '# G6a ledger-only clone, git status --porcelain:\n'
    printf '%s\n' "$G6A_STATUS" | sed 's/^/# /'
    assert_eq "?? .gsd/" "$G6A_STATUS" "G6a status"
    run bash "$INSTALL" "$TMP/clone a" --uninstall
    assert_rc 0 "G6a uninstall"
    [ ! -e "$TMP/clone a/.gsd/capabilities/ui-stitch" ] || fail "G6a staged dir still present"
    assert_hooks_in "$TMP/clone a" absent "G6a hooks after uninstall"

    git -C "$S" checkout -q -b case-b
    git -C "$S" rm -q --cached -- .gsd-capabilities.json
    git -C "$S" commit -qm "case b: nothing committed"
    gclone "$S" "$TMP/clone b" case-b
    mkdir -p "$TMP/gsdhome-g7"
    export GSD_HOME="$TMP/gsdhome-g7"
    assert_hooks_in "$TMP/clone b" absent "G6b hooks before registration"
    run bash "$INSTALL" "$TMP/clone b" --register-only
    assert_rc 0 "G6b --register-only"
    assert_hooks_in "$TMP/clone b" active "G6b hooks"
    case "$OUT" in *".gsd-capabilities.json ("*) fail "G6b printed a ledger line: $OUT" ;; esac
    G6B_STATUS="$(git -C "$TMP/clone b" status --porcelain)"
    printf '# G6b nothing-committed clone, git status --porcelain:\n'
    printf '%s\n' "$G6B_STATUS" | sed 's/^/# /'
    case "$G6B_STATUS" in *"?? .gsd-capabilities.json"*) ;; *) fail "G6b status lacks ?? .gsd-capabilities.json: $G6B_STATUS" ;; esac
    case "$G6B_STATUS" in *"?? .gsd/"*) ;; *) fail "G6b status lacks ?? .gsd/: $G6B_STATUS" ;; esac
    run bash "$INSTALL" "$TMP/clone b" --uninstall
    assert_rc 0 "G6b uninstall"
    [ ! -e "$TMP/clone b/.gsd/capabilities/ui-stitch" ] || fail "G6b staged dir still present"
    assert_hooks_in "$TMP/clone b" absent "G6b hooks after uninstall"
    ok "G6: ledger-only clone -> active, status '?? .gsd/'; nothing-committed clone -> active, both untracked; uninstall works in both"
  fi
fi

printf 'ALL TESTS PASSED\n'
