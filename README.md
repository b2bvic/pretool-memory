# pretool-memory

Vault-based memory recall for Claude Code. Your vault is the brain. This hook makes Claude read it before every tool call.

## What it does

Claude Code forgets everything between sessions. This hook gives it memory by searching your Obsidian vault (or any markdown folder) before every tool call and injecting relevant context into the conversation.

Claude is about to read a file? The hook checks your vault for related content first. Claude is about to search? The hook surfaces what you've already found. The context arrives before the tool fires, so Claude's next action is informed by everything you've already written.

## How it works

```
Claude thinks → PreToolUse hook fires → extract last thinking block →
hash-check for dedup → query vault via QMD (BM25, ~200ms) →
query session ledger via FTS5 (~30ms, optional) →
inject combined context → Claude proceeds
```

One shell script. No API keys. No cloud. No database server. Runs locally against your markdown files.

## Install

```bash
curl -sL https://raw.githubusercontent.com/b2bvic/pretool-memory/main/install.sh | bash
```

Or manually:

```bash
# Copy the hook
mkdir -p ~/.claude/hooks
cp pretool-memory.sh ~/.claude/hooks/
chmod +x ~/.claude/hooks/pretool-memory.sh

# Index your vault
cd /path/to/your/vault
qmd collection add .

# Add to Claude Code settings
# In ~/.claude/settings.json, add under "hooks":
```

```json
{
  "hooks": {
    "PreToolUse": [
      {
        "matcher": "",
        "hooks": [
          {
            "type": "command",
            "command": "bash ~/.claude/hooks/pretool-memory.sh"
          }
        ]
      }
    ]
  }
}
```

## Requirements

- [Claude Code](https://docs.anthropic.com/en/docs/claude-code) (any plan)
- [QMD](https://github.com/aethermonkey/qmd) for vault search (the hook exits silently without it)
- `jq` for JSON parsing
- A folder of markdown files (Obsidian vault, Zettelkasten, notes directory — any structure)
- Optional: [session-ledger](https://github.com/b2bvic/session-ledger) for cross-session history search

## Architecture

```
┌─────────────────────────────────────────┐
│ Claude Code Session                      │
│                                          │
│  Claude thinks...                        │
│       ↓                                  │
│  PreToolUse fires                        │
│       ↓                                  │
│  ┌──────────────────────────┐            │
│  │ pretool-memory.sh        │            │
│  │  1. Read transcript tail │            │
│  │  2. Extract thinking     │            │
│  │  3. Hash check (dedup)   │            │
│  │  4. Time check (30s)     │            │
│  │  5. Build search query   │            │
│  │  6. QMD BM25 search      │ ~200ms     │
│  │  7. Ledger FTS5 search   │ ~30ms      │
│  │  8. Inject results       │            │
│  └──────────────────────────┘            │
│       ↓                                  │
│  Tool executes with vault context        │
└─────────────────────────────────────────┘
```

## Performance

- QMD BM25 search: ~166ms average
- Session ledger FTS5: ~30ms average
- Dedup hash check: <1ms
- 30-second throttle prevents token bloat during rapid tool calls
- Content-hash dedup skips identical thinking blocks
- Fires only on read-oriented tools (Read, Glob, Grep, WebFetch, WebSearch, Task)
- Skips writes, bash, and self-referential QMD calls
- Total budget: <500ms (synchronous hook)

## Configuration

| Variable | Default | What it does |
|----------|---------|--------------|
| `LEDGER_DB` | `~/.claude/session-ledger.db` | Session ledger database path |
| Throttle | 30s | Minimum time between fires. Edit line 68. |
| Query length | 300 chars | Max search query from thinking block. Edit line 91. |
| Results | 3 | Number of vault matches returned. Edit line 109. |
| Min score | 0.3 | BM25 relevance threshold. Edit line 109. |
| Tool filter | Read,Glob,Grep,WebFetch,WebSearch,Task | Which tools trigger the hook. Edit line 33-37. |

## What this is extracted from

This hook runs inside a larger system — an Obsidian vault with 12,000+ files, 60+ Claude Code skills, semantic search, session ledger with 37,000+ messages, and automated workflows across multiple domains.

The vault is the memory. Claude Code is the operator. This hook is the bridge between them.

If you want the full system built for your business: [scalewithsearch.com](https://scalewithsearch.com)

## License

MIT

## Built by

[Victor Valentine Romo](https://b2bvic.com) — [Scale With Search](https://scalewithsearch.com)
