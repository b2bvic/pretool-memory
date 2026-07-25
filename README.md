# pretool-memory

Claude Code hook that injects relevant vault content mid-conversation. Extracts Claude's current thinking from the live transcript, searches your vault, and injects matching context before tool execution.

Built by [Victor Valentine Romo](https://victorvalentineromo.com) at [Scale With Search](https://scalewithsearch.com).

Part of a larger system: this repository proves **P02 (own the memory plane)** and **P03 (continuity compounds)** from the [Seventeen Principles](https://victorvalentineromo.com/principles). The memory being injected lives in plain text you own, and every session starts on the record earlier sessions left.

## What It Does

Every time Claude is about to use a tool (Read, Grep, Bash, etc.), this hook fires:

1. Reads the active JSONL transcript
2. Extracts the last `thinking` block (what Claude is reasoning about)
3. Hashes the thinking content to avoid duplicate queries (30s throttle)
4. Searches your vault via QMD (BM25 keyword search, ~166ms measured on the author's M4 Pro; your hardware will vary)
5. Optionally queries a session ledger SQLite database (FTS5, ~30ms on the same machine)
6. Injects matched content as `additionalContext` before the tool runs

Claude's next action is informed by relevant past sessions and vault content — without you having to manually reference anything.

## Install

```bash
# Copy the hook
cp pretool-memory.sh /path/to/your/project/.claude/hooks/

# Make executable
chmod +x /path/to/your/project/.claude/hooks/pretool-memory.sh

# Add to .claude/settings.json
```

Add to your project's `.claude/settings.json`:

```json
{
  "hooks": {
    "PreToolUse": [
      {
        "matcher": "",
        "hooks": [
          {
            "type": "command",
            "command": "bash .claude/hooks/pretool-memory.sh"
          }
        ]
      }
    ]
  }
}
```

## Requirements

- [QMD](https://github.com/aethermonkey/qmd) for vault search (BM25). Install: `bun install -g qmd && qmd index`
- Optional: [session-ledger](https://github.com/b2bvic/session-ledger) for cross-session search
- `jq` for JSON output encoding

## Configuration

| Variable | Default | Purpose |
|----------|---------|---------|
| `LEDGER_DB` | `~/.claude/session-ledger.db` | Session ledger database path |

## Performance

- QMD BM25 search: ~166ms average
- Session ledger FTS5: ~30ms average
- Dedup hash check: <1ms
- Throttle: 30 seconds between queries (prevents flooding)
- Total budget: <500ms (synchronous hook)

## License

MIT

## How this was built

Specification and judgment: human. Implementation: AI models executing that specification under a build contract, with an adversarial audit before publish. The division of labor is the point; see [P07](https://victorvalentineromo.com/principles).
