#!/bin/bash
# PreToolUse Semantic Memory Hook
# Extracts Claude's recent thinking from the live transcript,
# queries the vault (QMD BM25) and session ledger (FTS5), and injects
# relevant context before tool execution. Self-deduplicating via hash.
#
# Architecture:
#   PreToolUse fires → extract thinking → hash check → QMD search →
#   ledger search → inject combined context
#
# The hook is synchronous. Search latency depends on local hardware and index size.
#
# REQUIRES: QMD (https://github.com/aethermonkey/qmd) installed and indexed.
# If QMD is not available, vault search is skipped.
# Optional: session-ledger SQLite DB for cross-session history search.

# Always exit 0 so we never block tool execution
trap 'exit 0' ERR

# ===== READ STDIN =====
INPUT=$(cat)

TOOL_NAME=$(echo "$INPUT" | jq -r '.tool_name // ""' 2>/dev/null)
TRANSCRIPT_PATH=$(echo "$INPUT" | jq -r '.transcript_path // ""' 2>/dev/null)
SESSION_ID=$(echo "$INPUT" | jq -r '.session_id // "default"' 2>/dev/null)

# ===== CONFIGURATION =====
STATE_DIR="${PRETOOL_MEMORY_STATE_DIR:-/tmp/claude-memory}"
THROTTLE_SECONDS="${PRETOOL_THROTTLE_SECONDS:-30}"
MIN_THINKING_CHARS="${PRETOOL_MIN_THINKING_CHARS:-100}"

# ===== TOOL FILTER =====
# Only fire for read-oriented tools where Claude is gathering context.
# Skip writes (intent locked), QMD (avoid circular), browser, bash.
case "$TOOL_NAME" in
  Read|Glob|Grep|WebFetch|WebSearch|Task)
    ;; # proceed — these are exploration/research tools
  *)
    exit 0
    ;;
esac

# ===== TRANSCRIPT CHECK =====
if [ -z "$TRANSCRIPT_PATH" ] || [ ! -f "$TRANSCRIPT_PATH" ]; then
  exit 0
fi

# ===== EXTRACT LAST THINKING BLOCK =====
# tail is O(1) from end — safe even on 1GB+ transcripts.
# Pull last 200 lines, find thinking blocks, take last 1500 chars.
THINKING=$(tail -200 "$TRANSCRIPT_PATH" 2>/dev/null | \
  jq -r 'select(.type == "assistant") | .message.content[]? | select(.type == "thinking") | .thinking' 2>/dev/null | \
  tail -c 1500)

# Need enough thinking to form a meaningful query
if [ -z "$THINKING" ] || [ ${#THINKING} -lt "$MIN_THINKING_CHARS" ]; then
  exit 0
fi

# ===== TIME-BASED THROTTLE (30s) =====
# Prevents token bloat from rapid-fire tool calls in the same reasoning arc.
# The hash dedup below handles content dedup; this handles temporal dedup.
HASH_DIR="$STATE_DIR"
mkdir -p "$HASH_DIR" 2>/dev/null
THROTTLE_FILE="$HASH_DIR/${SESSION_ID}.last_fire"

if [ -f "$THROTTLE_FILE" ]; then
  LAST_FIRE=$(cat "$THROTTLE_FILE" 2>/dev/null)
  NOW=$(date +%s)
  ELAPSED=$(( NOW - LAST_FIRE ))
  if [ "$ELAPSED" -lt "$THROTTLE_SECONDS" ]; then
    exit 0
  fi
fi

# ===== HASH DEDUP =====
# Same thinking = same query = same results. Skip.
HASH_FILE="$HASH_DIR/${SESSION_ID}.hash"

# Portable: macOS uses `md5 -q`, Linux uses `md5sum`
CURRENT_HASH=$(echo "$THINKING" | md5 -q 2>/dev/null || echo "$THINKING" | md5sum 2>/dev/null | cut -d' ' -f1)

if [ -f "$HASH_FILE" ] && [ "$(cat "$HASH_FILE" 2>/dev/null)" = "$CURRENT_HASH" ]; then
  exit 0
fi

echo "$CURRENT_HASH" > "$HASH_FILE"

# ===== BUILD QUERY =====
# Take last 500 chars of thinking (most recent reasoning = most relevant intent).
# Strip non-alphanumeric noise (code symbols, JSON, etc.) for clean BM25 matching.
QUERY=$(echo "$THINKING" | tail -c 500 | tr '\n' ' ' | sed 's/[^a-zA-Z0-9 ._/-]/ /g' | tr -s ' ' | head -c 300)

if [ -z "$QUERY" ] || [ ${#QUERY} -lt 20 ]; then
  exit 0
fi

# ===== QUERY QMD (BM25 ~166ms) =====
# Try common install locations. If QMD isn't found, skip vault search.
QMD_BIN=""
if [ -n "${PRETOOL_QMD_BIN:-}" ] && [ -x "$PRETOOL_QMD_BIN" ]; then
  QMD_BIN="$PRETOOL_QMD_BIN"
elif [ "${PRETOOL_DISABLE_QMD:-0}" != "1" ]; then
  for candidate in \
    "$HOME/.bun/bin/qmd" \
    "$HOME/.local/bin/qmd" \
    "/usr/local/bin/qmd" \
    "$(command -v qmd 2>/dev/null)"; do
    if [ -n "$candidate" ] && [ -x "$candidate" ]; then
      QMD_BIN="$candidate"
      break
    fi
  done
fi

QMD_HIT=0
RESULTS=""
if [ -n "$QMD_BIN" ]; then
  RESULTS=$("$QMD_BIN" search "$QUERY" -n 3 --min-score 0.3 2>/dev/null)
  if [ -n "$RESULTS" ] && ! echo "$RESULTS" | grep -qi "no results found"; then
    QMD_HIT=1
  fi
fi

# ===== QUERY SESSION LEDGER (FTS5 ~30ms) =====
# Direct sqlite3 call — avoids Python startup overhead.
# Searches raw conversation history from all past Claude Code sessions.
LEDGER_DB="${LEDGER_DB:-$HOME/.claude/session-ledger.db}"
LEDGER_RESULTS=""
LEDGER_HIT=0

if [ "${PRETOOL_DISABLE_LEDGER:-0}" != "1" ] && [ -f "$LEDGER_DB" ]; then
  # Sanitize query for FTS5: strip operators, quotes, parens
  FTS_QUERY=$(echo "$QUERY" | sed 's/["(){}*^~]/ /g' | tr -s ' ' | head -c 200)

  if [ -n "$FTS_QUERY" ] && [ ${#FTS_QUERY} -ge 10 ]; then
    LEDGER_RESULTS=$(sqlite3 "$LEDGER_DB" "
      SELECT '  [' || COALESCE(domain, '?') || '] ' || COALESCE(timestamp, '') || ' — ' ||
             substr(replace(content_text, char(10), ' '), 1, 200)
      FROM fts_unified
      WHERE fts_unified MATCH '$(echo "$FTS_QUERY" | sed "s/'/''/g")'
      ORDER BY rank
      LIMIT 2;
    " 2>/dev/null)

    if [ -n "$LEDGER_RESULTS" ]; then
      LEDGER_HIT=1
    fi
  fi
fi

# ===== BAIL IF NOTHING FOUND =====
if [ "$QMD_HIT" -eq 0 ] && [ "$LEDGER_HIT" -eq 0 ]; then
  exit 0
fi

# ===== INJECT CONTEXT =====
CONTEXT="# Mid-Stream Memory Recall
(auto-injected by PreToolUse hook)"

if [ "$QMD_HIT" -eq 1 ]; then
  CONTEXT="$CONTEXT

## Vault Content (QMD BM25)
$RESULTS"
fi

if [ "$LEDGER_HIT" -eq 1 ]; then
  CONTEXT="$CONTEXT

## Past Session History (Ledger FTS5)
$LEDGER_RESULTS"
fi

CONTEXT="$CONTEXT

---
If this context changes your approach, adjust before proceeding."

# ===== RECORD FIRE TIME =====
date +%s > "$THROTTLE_FILE"

if command -v jq &> /dev/null; then
  ESCAPED=$(echo "$CONTEXT" | jq -Rs .)
  echo "{\"hookSpecificOutput\":{\"hookEventName\":\"PreToolUse\",\"additionalContext\":$ESCAPED}}"
fi

exit 0
