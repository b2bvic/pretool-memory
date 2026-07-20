# Failure modes

| Failure | Observable behavior | Containment |
|---|---|---|
| Malformed hook JSON | No output; exit zero | Underlying tool proceeds. |
| Transcript path missing | No output; exit zero | Underlying tool proceeds. |
| No useful thinking block | No output; exit zero | Minimum-length gate avoids a weak query. |
| `jq` unavailable | No output; exit zero | Install check and CI cover the declared dependency. |
| QMD unavailable or returns no result | Ledger may still run; otherwise no output | Retrieval backend is optional at runtime. |
| Ledger missing, incompatible, or `sqlite3` unavailable | QMD may still supply context | Ledger errors are discarded. |
| State directory unavailable | No output; exit zero | The hook does not block the tool call. |
| Search is slow | Tool call waits because the hook is synchronous | Keep the index local and monitor latency separately. |
| Search result is irrelevant | Context is injected despite poor relevance | Tune the corpus and QMD threshold; the tests do not certify relevance. |
| Memory path silently degrades | Tool proceeds without recall | Add an external smoke check when recall is operationally required. |

The hook is not an authorization system, source-of-truth validator, or substitute for explicit context loading on high-risk work.
