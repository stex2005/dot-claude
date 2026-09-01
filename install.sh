#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TARGET_DIR="$HOME/.claude/commands"
DOCS_DIR="$HOME/.claude/docs"

mkdir -p "$TARGET_DIR" "$DOCS_DIR"

cp -f "$SCRIPT_DIR"/commands/*.md "$TARGET_DIR/"

# The stack-* commands cite these two files by absolute path at runtime
# (~/.claude/docs/...), because they run with the user's workspace as cwd, not
# this repository. They carry the canonical guard, manifest schema and jq
# snippets — without them an executor would improvise and corrupt the manifest.
cp -f "$SCRIPT_DIR"/docs/stacked-pr-workflow.md "$DOCS_DIR/"
cp -f "$SCRIPT_DIR"/docs/gh-stack-json-reference.md "$DOCS_DIR/"

echo "Installed dot-claude commands to $TARGET_DIR"
echo "Installed stacked-PR reference docs to $DOCS_DIR"
