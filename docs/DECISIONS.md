# Design decisions

## Fail open

This hook adds context to a tool call. It does not own the tool call. A retrieval failure therefore exits zero and emits no context instead of stopping the session.

Tradeoff: silent degradation is safer for interactive work, but it can hide a broken memory path. Operators who depend on recall need a separate health check.

## Read-oriented allowlist

The hook runs only before `Read`, `Glob`, `Grep`, `WebFetch`, `WebSearch`, and `Task`. Writes and shell execution are excluded because injecting new context after mutation intent has formed can create surprising changes in behavior.

## Transcript tail instead of full transcript

The query comes from the last thinking block in the last 200 transcript lines. This bounds I/O for large JSONL files and weights the current reasoning arc. It can miss an older intent that was not repeated.

## Two deduplication layers

The time throttle limits repeated retrieval during rapid tool calls. The content hash suppresses the same thinking block after the throttle expires. State is per session and stored outside the repository.

## Keyword retrieval before embeddings

QMD BM25 and optional SQLite FTS5 keep the synchronous path local and inspectable. The design does not claim that keyword retrieval is always more relevant than vector search.
