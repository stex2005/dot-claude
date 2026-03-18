#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TARGET_DIR="$HOME/.claude/commands"

mkdir -p "$TARGET_DIR"

# Remove old nested directory if it exists
rm -rf "$TARGET_DIR/claude-code-workflow"

cp "$SCRIPT_DIR"/*.md "$TARGET_DIR/"

echo "Installed claude-code-workflow commands to $TARGET_DIR"
