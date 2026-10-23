#!/usr/bin/env bash
# One-command install of the gsd-stitch-design pack, always from the latest release.
#
#   curl -fsSL https://raw.githubusercontent.com/EthanChenGuang/gsd-stitch-design/main/bootstrap.sh | bash
#   curl -fsSL .../bootstrap.sh | bash -s -- [project-dir] [install.sh flags]
#
# Downloads the newest release (or GSD_STITCH_REF, e.g. v1.2.0 or main) into
# ~/.cache/gsd-stitch-design/<ref>, runs install.sh on the project (default: the
# current directory), then stages every file a normal install writes so one
# `git commit` finishes the job. Flags such as --dry-run, --register-only,
# --uninstall, --force and --no-autonomous are passed to install.sh unchanged.
# It stops without writing anything when GSD or .planning/ is missing (override with
# --skip-gsd-check). A full install also adds a SessionStart hook that re-registers the capability in
# fresh cloud containers (skip it with --no-hook); --uninstall removes it again.
set -euo pipefail

REPO="EthanChenGuang/gsd-stitch-design"
CACHE_ROOT="${XDG_CACHE_HOME:-$HOME/.cache}/gsd-stitch-design"

say() { printf 'gsd-stitch-design: %s\n' "$*"; }
die() { printf 'gsd-stitch-design: %s\n' "$*" >&2; exit 1; }

command -v curl >/dev/null || die "curl is required"
command -v tar >/dev/null || die "tar is required"
command -v node >/dev/null || die "node is required (the installer and GSD both need it)"

target="."
flags=()
with_hook=1
check_gsd=1
for arg in "$@"; do
  case "$arg" in
    --no-hook) with_hook=0 ;;
    --skip-gsd-check) check_gsd=0 ;;
    -*) flags+=("$arg") ;;
    *) target="$arg" ;;
  esac
done
[ -d "$target" ] || die "project directory not found: $target"
target="$(cd "$target" && pwd)"

# The skills only work inside a GSD project, so stop before writing anything when GSD
# or the project's .planning/ is missing (uninstall and help still run).
needs_gsd=1
for arg in ${flags[@]+"${flags[@]}"}; do
  case "$arg" in --uninstall|-h|--help) needs_gsd=0 ;; esac
done
if [ "$check_gsd" = 1 ] && [ "$needs_gsd" = 1 ]; then
  missing=()
  if [ ! -f "$target/.claude/gsd-core/bin/gsd-tools.cjs" ] && [ ! -f "$HOME/.claude/gsd-core/bin/gsd-tools.cjs" ] \
    && ! command -v gsd_run >/dev/null 2>&1; then
    missing+=("GSD is not installed (no .claude/gsd-core in the project or in ~/.claude). Install it: npx -y @opengsd/gsd-core@latest --claude --local")
  fi
  if [ ! -f "$target/.planning/config.json" ]; then
    missing+=("this is not a GSD project yet (no .planning/config.json). Run /gsd-new-project in Claude Code first.")
  fi
  if [ "${#missing[@]}" -gt 0 ]; then
    printf 'gsd-stitch-design: ERROR: nothing was installed in %s\n' "$target" >&2
    for m in "${missing[@]}"; do printf '  - %s\n' "$m" >&2; done
    printf '  Then run this command again. (--skip-gsd-check installs the skills anyway.)\n' >&2
    exit 1
  fi
fi

# Resolve the newest release tag unless a ref was pinned.
ref="${GSD_STITCH_REF:-}"
if [ -z "$ref" ]; then
  ref="$(curl -fsSL "https://api.github.com/repos/$REPO/releases/latest" 2>/dev/null \
    | node -e 'let s="";process.stdin.on("data",d=>s+=d).on("end",()=>{try{process.stdout.write(JSON.parse(s).tag_name||"")}catch{}})' || true)"
  [ -n "$ref" ] || { ref="main"; say "could not read the latest release; using main"; }
fi

# A release is immutable, so a cached copy is reused; main is always fetched fresh.
pack="$CACHE_ROOT/$ref"
if [ "$ref" = "main" ] || [ ! -f "$pack/install.sh" ]; then
  tmp="$(mktemp -d)"
  trap 'rm -rf "$tmp"' EXIT
  curl -fsSL "https://github.com/$REPO/archive/$ref.tar.gz" -o "$tmp/pack.tar.gz" \
    || die "download failed for $ref"
  mkdir -p "$tmp/pack"
  tar -xzf "$tmp/pack.tar.gz" -C "$tmp/pack" --strip-components=1
  [ -f "$tmp/pack/install.sh" ] || die "the download for $ref has no install.sh"
  rm -rf "$pack"
  mkdir -p "$CACHE_ROOT"
  mv "$tmp/pack" "$pack"
fi
say "pack $ref ($(cat "$pack/VERSION" 2>/dev/null || echo '?')) from $pack"

bash "$pack/install.sh" "$target" ${flags[@]+"${flags[@]}"}

mode=install
for f in ${flags[@]+"${flags[@]}"}; do
  case "$f" in
    --dry-run|--register-only|-h|--help) exit 0 ;;
    --uninstall) mode=uninstall ;;
  esac
done

# Cloud sessions start in fresh containers without the GSD consent record in ~/.gsd, so a
# SessionStart hook re-registers the capability there. It does nothing on a local machine.
hook_file=".claude/hooks/gsd-stitch-design.sh"
hook_cmd='bash "$CLAUDE_PROJECT_DIR/.claude/hooks/gsd-stitch-design.sh"'
settings_hook() { # $1 = add | remove
  SETTINGS="$target/.claude/settings.json" CMD="$hook_cmd" ACTION="$1" node -e '
    const fs = require("fs"), f = process.env.SETTINGS, cmd = process.env.CMD
    let j = {}
    if (fs.existsSync(f)) { try { j = JSON.parse(fs.readFileSync(f, "utf8")) } catch { console.error("WARN: " + f + " is not valid JSON; hook entry not changed"); process.exit(0) } }
    const groups = ((j.hooks = j.hooks || {}).SessionStart = j.hooks.SessionStart || [])
    const has = (g) => (g.hooks || []).some((h) => h.command === cmd)
    if (process.env.ACTION === "add") {
      if (groups.some(has)) process.exit(0)
      groups.push({ hooks: [{ type: "command", command: cmd }] })
    } else {
      j.hooks.SessionStart = groups.filter((g) => !has(g))
      if (!j.hooks.SessionStart.length) delete j.hooks.SessionStart
      if (!Object.keys(j.hooks).length) delete j.hooks
    }
    if (!Object.keys(j).length) { if (fs.existsSync(f)) fs.unlinkSync(f); process.exit(0) }
    fs.writeFileSync(f, JSON.stringify(j, null, 2) + "\n")'
}

if [ "$mode" = uninstall ]; then
  if [ -f "$target/$hook_file" ]; then
    rm -f "$target/$hook_file"
    [ -f "$target/.claude/settings.json" ] && settings_hook remove
    say "removed the SessionStart re-registration hook"
  fi
  exit 0
fi

if [ "$with_hook" = 1 ]; then
  mkdir -p "$target/.claude/hooks"
  cat > "$target/$hook_file" <<'HOOK'
#!/usr/bin/env bash
# Installed by gsd-stitch-design: re-register the ui-stitch GSD capability in a fresh cloud
# container, where the consent record in ~/.gsd does not exist yet. No-op on local machines.
[ "${CLAUDE_CODE_REMOTE:-}" = "true" ] || exit 0
curl -fsSL https://raw.githubusercontent.com/EthanChenGuang/gsd-stitch-design/main/bootstrap.sh \
  | bash -s -- "${CLAUDE_PROJECT_DIR:-.}" --register-only >/dev/null 2>&1 || true
exit 0
HOOK
  chmod +x "$target/$hook_file"
  settings_hook add
  say "SessionStart hook ready: cloud sessions re-register automatically"
fi

# Stage what the install wrote so one commit finishes the job.
git -C "$target" rev-parse --is-inside-work-tree >/dev/null 2>&1 || exit 0
staged=()
for path in \
  .claude/skills/gsd-ui-stitch-phase .claude/skills/gsd-ui-design-pick .claude/skills/.gsd-stitch-design-version \
  .claude/CLAUDE.md CLAUDE.md .planning/design/design-config.json .planning/config.json .gsd-capabilities.json \
  "$hook_file" .claude/settings.json; do
  [ -e "$target/$path" ] && git -C "$target" add -- "$path" && staged+=("$path")
done
# GSD writes .gsd/.gitignore containing "*", so this one file needs -f.
cap=".gsd/capabilities/ui-stitch/capability.json"
[ -f "$target/$cap" ] && git -C "$target" add -f -- "$cap" && staged+=("$cap")
if [ "${#staged[@]}" -gt 0 ]; then
  say "done. Staged ${#staged[@]} paths; finish with:"
  printf '  git -C %q commit -m "Install gsd-stitch-design %s" && git -C %q push\n' "$target" "$ref" "$target"
fi
