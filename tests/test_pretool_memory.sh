#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
HOOK="$ROOT_DIR/pretool-memory.sh"
TEST_DIR=$(mktemp -d)
trap 'rm -rf "$TEST_DIR"' EXIT

TRANSCRIPT="$TEST_DIR/transcript.jsonl"
STATE_DIR="$TEST_DIR/state"
FAKE_QMD="$TEST_DIR/qmd"

printf '%s\n' '#!/usr/bin/env bash' 'printf "%s\n" "fixture://vault/design.md: fail-open retrieval with deterministic context"' > "$FAKE_QMD"
chmod +x "$FAKE_QMD"

LONG_THINKING="I need to inspect the retrieval design before reading implementation files. The memory hook should recall prior decisions, preserve a fail-open boundary, and avoid repeating the same search during one reasoning arc."
printf '%s\n' "$(jq -nc --arg thinking "$LONG_THINKING" '{type:"assistant",message:{content:[{type:"thinking",thinking:$thinking}]}}')" > "$TRANSCRIPT"

invoke() {
  local input="$1"
  printf '%s' "$input" | \
    PRETOOL_MEMORY_STATE_DIR="$STATE_DIR" \
    PRETOOL_QMD_BIN="$FAKE_QMD" \
    PRETOOL_DISABLE_LEDGER=1 \
    bash "$HOOK"
}

hook_input() {
  local tool="$1"
  local transcript="$2"
  local session="$3"
  jq -nc --arg tool "$tool" --arg transcript "$transcript" --arg session "$session" \
    '{tool_name:$tool,transcript_path:$transcript,session_id:$session}'
}

assert_empty() {
  local value="$1"
  local label="$2"
  if [[ -n "$value" ]]; then
    printf 'FAIL: %s emitted unexpected output: %s\n' "$label" "$value" >&2
    exit 1
  fi
}

unsupported=$(invoke "$(hook_input Write "$TRANSCRIPT" unsupported)")
assert_empty "$unsupported" "unsupported tool"

missing=$(invoke "$(hook_input Read "$TEST_DIR/missing.jsonl" missing)")
assert_empty "$missing" "missing transcript"

malformed=$(invoke '{not-json')
assert_empty "$malformed" "malformed input"

valid=$(invoke "$(hook_input Read "$TRANSCRIPT" valid)")
jq -e '.hookSpecificOutput.hookEventName == "PreToolUse"' <<< "$valid" >/dev/null
jq -e '.hookSpecificOutput.additionalContext | contains("fixture://vault/design.md")' <<< "$valid" >/dev/null

printf '%s\n' "$(jq -nc --arg thinking "${LONG_THINKING} A different ending changes the hash but should still be throttled." '{type:"assistant",message:{content:[{type:"thinking",thinking:$thinking}]}}')" >> "$TRANSCRIPT"
throttled=$(invoke "$(hook_input Read "$TRANSCRIPT" valid)")
assert_empty "$throttled" "time throttle"

dedup_state="$TEST_DIR/dedup-state"
first=$(printf '%s' "$(hook_input Read "$TRANSCRIPT" dedup)" | \
  PRETOOL_MEMORY_STATE_DIR="$dedup_state" PRETOOL_THROTTLE_SECONDS=0 \
  PRETOOL_QMD_BIN="$FAKE_QMD" PRETOOL_DISABLE_LEDGER=1 bash "$HOOK")
second=$(printf '%s' "$(hook_input Read "$TRANSCRIPT" dedup)" | \
  PRETOOL_MEMORY_STATE_DIR="$dedup_state" PRETOOL_THROTTLE_SECONDS=0 \
  PRETOOL_QMD_BIN="$FAKE_QMD" PRETOOL_DISABLE_LEDGER=1 bash "$HOOK")
[[ -n "$first" ]]
assert_empty "$second" "content deduplication"

no_backend=$(printf '%s' "$(hook_input Read "$TRANSCRIPT" no-backend)" | \
  PRETOOL_MEMORY_STATE_DIR="$TEST_DIR/no-backend-state" \
  PRETOOL_DISABLE_QMD=1 PRETOOL_DISABLE_LEDGER=1 bash "$HOOK")
assert_empty "$no_backend" "missing retrieval backends"

printf 'PASS: pretool-memory contract tests\n'
