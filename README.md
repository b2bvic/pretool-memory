# pretool-memory

Local memory recall for Claude Code before read-oriented tool calls.

`pretool-memory.sh` reads the latest thinking block from Claude Code's JSONL transcript, builds a bounded query, searches a local Markdown index and optional session ledger, then injects matching context into the current turn. It exits successfully and emits nothing when it cannot retrieve useful context, so memory failure does not block the underlying tool.

## The control path

```text
PreToolUse JSON
  -> allowlisted read tool
  -> transcript tail
  -> minimum useful thinking block
  -> per-session time throttle
  -> content-hash deduplication
  -> QMD BM25 and optional SQLite FTS5
  -> hookSpecificOutput.additionalContext
```

The implementation is one Bash script. It uses no cloud service and no API key.

## Verify it

```bash
bash -n pretool-memory.sh install.sh tests/test_pretool_memory.sh
bash tests/test_pretool_memory.sh
```

The contract tests use a temporary transcript, state directory, and deterministic fake QMD executable. They cover:

- unsupported tools and missing transcripts
- malformed hook input
- successful context injection
- time throttling and content deduplication
- missing retrieval backends

## Install

```bash
git clone https://github.com/b2bvic/pretool-memory.git
cd pretool-memory
bash install.sh
```

Then index the Markdown directory you want QMD to search and add the hook to Claude Code's `PreToolUse` configuration. See the settings fragment printed by `install.sh`.

## Requirements

- [Claude Code](https://docs.anthropic.com/en/docs/claude-code)
- `bash` and `jq`
- [QMD](https://github.com/aethermonkey/qmd) with a local collection
- Optional: [session-ledger](https://github.com/b2bvic/session-ledger) and `sqlite3`

Without QMD or a compatible ledger database, the hook exits silently.

## Configuration

| Environment variable | Default | Purpose |
|---|---:|---|
| `LEDGER_DB` | `~/.claude/session-ledger.db` | Optional SQLite FTS5 database. |
| `PRETOOL_MEMORY_STATE_DIR` | `/tmp/claude-memory` | Per-session hash and throttle files. |
| `PRETOOL_THROTTLE_SECONDS` | `30` | Minimum interval between recalls for one session. |
| `PRETOOL_MIN_THINKING_CHARS` | `100` | Rejects fragments too short to form a useful query. |
| `PRETOOL_QMD_BIN` | auto-detected | Explicit path to the QMD executable. |
| `PRETOOL_DISABLE_QMD` | `0` | Set to `1` to suppress QMD lookup. |
| `PRETOOL_DISABLE_LEDGER` | `0` | Set to `1` to suppress ledger lookup. |

## Latency boundary

The hook is synchronous, so retrieval latency is added to the tool call. A March 2026 local measurement on the author's machine observed roughly 166 ms for QMD BM25 and 30 ms for SQLite FTS5. Those figures are not a portable benchmark. Corpus size, hardware, index state, and executable startup time will change them.

The 30-second throttle and content hash reduce repeated work during one reasoning arc. The test suite verifies control flow, not retrieval quality or a latency service level.

## Failure semantics

The script deliberately traps errors and exits zero. That keeps a missing binary, malformed transcript, empty search result, or broken optional ledger from blocking Claude Code. It also means operators need separate health checks if memory retrieval is business-critical.

See [failure modes](docs/FAILURE-MODES.md) and [design decisions](docs/DECISIONS.md).

## Public proof boundary

This repository contains the hook, installer, deterministic contract tests, and design records. It does not contain a private vault, transcript corpus, QMD index, or session ledger. Search relevance depends on the operator's own corpus and index configuration.

## License

MIT

Built by [Victor Valentine Romo](https://b2bvic.com).
