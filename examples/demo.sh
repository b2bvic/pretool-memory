#!/usr/bin/env bash
# Isolated, synthetic demonstration. Does not install hooks or contact a model.
set -euo pipefail
REPO_ROOT=$(CDPATH="" cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
demo_root=$(mktemp -d)
trap 'rm -rf "$demo_root"' EXIT
cat > "$demo_root/qmd" <<'SEARCH'
#!/bin/sh
printf '%s\n' 'Synthetic memory: retain source records and review decisions.'
SEARCH
chmod u+x "$demo_root/qmd"
python3 - "$demo_root/session.jsonl" <<'TRANSCRIPT'
import json
import sys
from pathlib import Path
thinking = "Review portable source records and prior decisions before choosing a workflow. " * 4
Path(sys.argv[1]).write_text(json.dumps({"type": "assistant", "message": {"content": [{"type": "thinking", "thinking": thinking}]}}) + "\n")
TRANSCRIPT
python3 - "$demo_root/session.jsonl" <<'INPUT' | QMD_BIN="$demo_root/qmd" MEMORY_STATE_DIR="$demo_root/cache" LEDGER_DB="$demo_root/absent.db" bash "$REPO_ROOT/pretool-memory.sh"
import json
import sys
print(json.dumps({"tool_name": "Read", "transcript_path": sys.argv[1], "session_id": "synthetic-demo"}))
INPUT
