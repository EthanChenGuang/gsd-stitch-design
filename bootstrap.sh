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
for arg in "$@"; do
  case "$arg" in
    -*) flags+=("$arg") ;;
    *) target="$arg" ;;
  esac
done
[ -d "$target" ] || die "project directory not found: $target"
target="$(cd "$target" && pwd)"

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

# Stage what a full install wrote; dry runs, uninstalls and re-registration leave git alone.
for f in ${flags[@]+"${flags[@]}"}; do
  case "$f" in --dry-run|--uninstall|--register-only|-h|--help) exit 0 ;; esac
done
git -C "$target" rev-parse --is-inside-work-tree >/dev/null 2>&1 || exit 0
staged=()
for path in \
  .claude/skills/gsd-ui-stitch-phase .claude/skills/gsd-ui-design-pick .claude/skills/.gsd-stitch-design-version \
  .claude/CLAUDE.md CLAUDE.md .planning/design/design-config.json .planning/config.json .gsd-capabilities.json; do
  [ -e "$target/$path" ] && git -C "$target" add -- "$path" && staged+=("$path")
done
# GSD writes .gsd/.gitignore containing "*", so this one file needs -f.
cap=".gsd/capabilities/ui-stitch/capability.json"
[ -f "$target/$cap" ] && git -C "$target" add -f -- "$cap" && staged+=("$cap")
if [ "${#staged[@]}" -gt 0 ]; then
  say "staged ${#staged[@]} paths. Finish with:"
  printf '  git -C %q commit -m "Install gsd-stitch-design %s"\n' "$target" "$ref"
fi
