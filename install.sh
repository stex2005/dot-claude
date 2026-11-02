#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TARGET_DIR="$HOME/.claude/commands"
DOCS_DIR="$HOME/.claude/docs"
SKILLS_DIR="$HOME/.claude/skills"

MANIFEST="$HOME/.claude/.dot-claude-manifest"

mkdir -p "$TARGET_DIR" "$DOCS_DIR" "$SKILLS_DIR"

# Paths (relative to ~/.claude) this install ships.
new_manifest="$(
  cd "$SCRIPT_DIR"
  ls commands/*.md
  for d in skills/*/; do basename "$d" | sed 's#^#skills/#'; done
  echo docs/stacked-pr-workflow.md
  echo docs/gh-stack-json-reference.md
)"

# Prune what a previous install shipped but this one no longer does. Without a
# manifest yet, fall back to files deleted from this repo's git history.
if [[ -f "$MANIFEST" ]]; then
  old_manifest="$(cat "$MANIFEST")"
else
  old_manifest="$(git -C "$SCRIPT_DIR" log --diff-filter=D --name-only --format= 2>/dev/null \
    | grep -E '^(commands|docs)/|^skills/[^/]+/' | sed -E 's#^(skills/[^/]+)/.*#\1#' | sort -u || true)"
fi
while IFS= read -r rel; do
  [[ -z "$rel" ]] && continue
  grep -qxF "$rel" <<<"$new_manifest" && continue
  if [[ -e "$HOME/.claude/$rel" ]]; then
    rm -rf -- "${HOME:?}/.claude/$rel"
    echo "Removed stale $rel"
  fi
done <<<"$old_manifest"

cp -f "$SCRIPT_DIR"/commands/*.md "$TARGET_DIR/"
cp -rf "$SCRIPT_DIR"/skills/. "$SKILLS_DIR/"

# The stack-* commands cite these two files by absolute path at runtime
# (~/.claude/docs/...), because they run with the user's workspace as cwd, not
# this repository. They carry the canonical guard, manifest schema and jq
# snippets — without them an executor would improvise and corrupt the manifest.
cp -f "$SCRIPT_DIR"/docs/stacked-pr-workflow.md "$DOCS_DIR/"
cp -f "$SCRIPT_DIR"/docs/gh-stack-json-reference.md "$DOCS_DIR/"

printf '%s\n' "$new_manifest" >"$MANIFEST"

echo "Installed dot-claude commands to $TARGET_DIR"
echo "Installed stacked-PR reference docs to $DOCS_DIR"
echo "Installed dot-claude skills to $SKILLS_DIR"
