# Changelog

## 0.1.0 - 2026-07-20

- Add deterministic contract tests and read-only GitHub Actions CI.
- Add environment seams for the state directory, throttle, minimum thinking length, QMD executable, and optional backend suppression.
- Document failure modes, design decisions, verification commands, and the public proof boundary.

The retrieval behavior remains fail-open. Missing or broken optional memory backends do not block the underlying Claude Code tool call.
