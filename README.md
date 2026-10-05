# Claude Code persistent memory hook: pretool-memory

pretool-memory retrieves local search results before selected Claude Code tool calls for operators using hosted Claude models.
It supplies candidate context from owned records when the current session needs earlier decisions.

[Project page](https://scalewithsearch.com/code/pretool-memory)

## Install

Requirements: Bash, `jq`, `shasum`, and a configured [QMD](https://github.com/tobi/qmd) Markdown collection.
Optional SQLite FTS5 session recall requires `sqlite3` and a compatible `fts_unified` table.

```sh
git clone https://github.com/b2bvic/pretool-memory.git
cd pretool-memory
```

The quick start also requires Python 3.
It uses synthetic search output and needs no QMD installation or model credentials.

## Quick start

```sh
bash examples/demo.sh
```

The demo builds a synthetic transcript and supplies a mock QMD executable.
It prints `PreToolUse` JSON with a sample `additionalContext` value.
Its temporary files are removed when the demo exits.

For real use, copy `pretool-memory.sh` into your project's `.claude/hooks/` directory.
Merge this opt-in entry into `.claude/settings.json` after reviewing the corpus:

```json
{
  "hooks": {
    "PreToolUse": [
      {
        "matcher": "Read|Glob|Grep|WebFetch|WebSearch|Task",
        "hooks": [
          {
            "type": "command",
            "command": "bash \"$CLAUDE_PROJECT_DIR/.claude/hooks/pretool-memory.sh\""
          }
        ]
      }
    ]
  }
}
```

Use the [Claude Code hook reference](https://code.claude.com/docs/en/hooks) when merging existing settings.

## How it works

AI agent memory retrieval follows a bounded transcript tail:

1. Filter calls to `Read`, `Glob`, `Grep`, `WebFetch`, `WebSearch`, or `Task`.
2. Read the last 200 transcript lines and retain up to 1,500 bytes of thinking text.
3. Skip short thinking, recent queries, and repeated thinking hashes.
4. Use QMD `search` for BM25 context retrieval with at most three results.
5. Query an optional SQLite ledger for at most two history snippets.
6. Emit the matches as `additionalContext`.

The hook uses a 30-second per-session throttle after a successful recall.
Session IDs become SHA-256 cache keys.
Search failures yield no result from that source; the other source can still supply context.

| Variable | Default | Purpose |
|---|---|---|
| `QMD_BIN` | `~/.bun/bin/qmd` | QMD executable or scoped search wrapper |
| `LEDGER_DB` | `~/.claude/session-ledger.db` | Optional SQLite ledger |
| `MEMORY_STATE_DIR` | `${XDG_CACHE_HOME:-$HOME/.cache}/pretool-memory` | Hash and throttle files |

## Portability

Memory resides in the source Markdown collection and optional SQLite ledger.
The export path is your collection directory and the database selected by `LEDGER_DB`.
The hook supplies no export command and does not create a ledger.

When changing model vendors, carry the original Markdown files and a consistent SQLite backup.
Rebuild the search index from those records and configure the next client's retrieval adapter.
The supplied `PreToolUse` adapter and thinking extraction target Claude Code.
Moving records does not make this hook compatible with another client.

## Limits

- Recall needs a readable transcript with an assistant thinking block of at least 100 characters.
- Hidden or absent thinking produces no recall.
- Retrieval can miss records or return unsuitable context.
- Write, Edit, and Bash calls do not trigger recall.
- Search has no internal wall-clock timeout or measured latency guarantee.
- The ledger schema must contain `domain`, `timestamp`, and `content_text` in `fts_unified`.
- Retrieved text remains untrusted evidence and can enter a hosted-model session.
- The hook returns success without acting as an approval gate.

## Verify

```sh
python3 -m unittest discover -s tests -v
bash -n pretool-memory.sh examples/demo.sh
shellcheck pretool-memory.sh examples/demo.sh
ruff check --select F,E9 tests
```

Tests use synthetic transcripts, a mock QMD command, and a temporary SQLite database.
Install ShellCheck and Ruff 0.16.10 for lint.

## Related repositories

- [owned-record](https://github.com/b2bvic/owned-record): Markdown context folders and routing configuration.
- [vault-crawl](https://github.com/b2bvic/vault-crawl): Retrieve source material and preserve provenance.
- [cc-bridge](https://github.com/b2bvic/cc-bridge): Convert transcript exchanges to Markdown logs.
- [voice-calibration](https://github.com/b2bvic/voice-calibration): Recall writing samples for a target file genre.

## License

MIT. See [LICENSE](LICENSE).
