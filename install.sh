#!/bin/bash
# Install pretool-memory for Claude Code
#
# What this does:
#   1. Copies the pretool-memory.sh hook to ~/.claude/hooks/
#   2. Checks for QMD and session-ledger availability
#   3. Shows settings.json configuration snippet
#
# Run: curl -sL https://raw.githubusercontent.com/b2bvic/pretool-memory/main/install.sh | bash

set -euo pipefail

HOOK_DIR="$HOME/.claude/hooks"
SETTINGS="$HOME/.claude/settings.json"
HOOK_URL="https://raw.githubusercontent.com/b2bvic/pretool-memory/main/pretool-memory.sh"

echo "Installing pretool-memory..."

# Create hooks directory
mkdir -p "$HOOK_DIR"

# Download the hook
curl -sL "$HOOK_URL" -o "$HOOK_DIR/pretool-memory.sh"
chmod +x "$HOOK_DIR/pretool-memory.sh"
echo "  Hook installed: $HOOK_DIR/pretool-memory.sh"

# Check for QMD
if command -v qmd &>/dev/null; then
    echo "  QMD found: $(which qmd)"
elif [ -x "$HOME/.bun/bin/qmd" ]; then
    echo "  QMD found: $HOME/.bun/bin/qmd"
else
    echo "  QMD not found. Install it for vault search: https://github.com/aethermonkey/qmd"
    echo "  The hook works without QMD but has nothing to search."
fi

# Check for jq
if ! command -v jq &>/dev/null; then
    echo "  WARNING: jq not found. Install it: brew install jq (macOS) or apt install jq (Linux)"
    echo "  The hook requires jq to parse Claude's input and format output."
fi

# Check for session ledger
LEDGER_DB="${LEDGER_DB:-$HOME/.claude/session-ledger.db}"
if [ -f "$LEDGER_DB" ]; then
    echo "  Session ledger found: $LEDGER_DB"
else
    echo "  No session ledger found (optional). See: https://github.com/b2bvic/session-ledger"
fi

# Add hook to settings.json if not already present
if [ -f "$SETTINGS" ]; then
    if grep -q "pretool-memory" "$SETTINGS" 2>/dev/null; then
        echo "  Hook already registered in settings.json"
    else
        echo ""
        echo "  Add this to your settings.json under \"hooks.PreToolUse\":"
        echo ""
        echo '    {"matcher": "", "hooks": [{"type": "command", "command": "bash '"$HOOK_DIR"'/pretool-memory.sh"}]}'
        echo ""
    fi
else
    echo "  No settings.json found at $SETTINGS"
    echo "  Run 'claude' once to initialize, then add the hook."
fi

echo ""
echo "Done. Index your vault: cd /path/to/vault && qmd collection add ."
echo "Then use Claude Code normally. Memory injection is automatic."
