import json
import os
import sqlite3
import subprocess
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SCRIPT = ROOT / "pretool-memory.sh"

class HookTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.base = Path(self.tmp.name)
        self.calls = self.base / "calls"
        self.result = self.base / "result"
        self.result.write_text('Sample "quoted" context\nsecond line')
        self.qmd = self.base / "qmd"
        self.qmd.write_text('#!/bin/sh\nprintf "%s\\n" "$*" >> "$TEST_CALLS"\ncat "$TEST_RESULT"\n')
        self.qmd.chmod(0o755)
        self.state = self.base / "cache"
        self.env = dict(os.environ, QMD_BIN=str(self.qmd),
                        TEST_CALLS=str(self.calls), TEST_RESULT=str(self.result),
                        MEMORY_STATE_DIR=str(self.state), VOICE_STATE_DIR=str(self.state),
                        LEDGER_DB=str(self.base / "missing.db"))

    def invoke(self, payload):
        proc = subprocess.run(["bash", str(SCRIPT)], input=payload if isinstance(payload, str) else json.dumps(payload),
                              text=True, capture_output=True, env=self.env)
        self.assertEqual(proc.returncode, 0, proc.stderr)
        self.assertEqual(proc.stderr, "")
        return json.loads(proc.stdout)["hookSpecificOutput"] if proc.stdout else None

    def test_invalid_input_is_silent(self):
        for payload in ['{invalid', '{}', '[]']:
            self.assertIsNone(self.invoke(payload))
        self.assertFalse(self.calls.exists())

    def test_missing_search_is_silent(self):
        self.env["QMD_BIN"] = str(self.base / "missing-command")
        self.assertIsNone(self.invoke(self.payload()))

    def test_no_results_can_retry(self):
        self.result.write_text("No results found.")
        self.assertIsNone(self.invoke(self.payload()))
        self.result.write_text("Owned Markdown context")
        self.assertIsNotNone(self.invoke(self.payload()))

    def test_session_id_cannot_escape_cache(self):
        payload = self.payload()
        payload["session_id"] = "../../escape"
        self.assertIsNotNone(self.invoke(payload))
        self.assertFalse((self.base / "escape").exists())
        self.assertTrue(all(p.parent == self.state for p in self.state.iterdir()))
        self.assertTrue(all(len(p.name.split('.')[0]) == 64 for p in self.state.iterdir()))

    def test_corrupt_throttle_is_ignored(self):
        self.assertIsNotNone(self.invoke(self.payload()))
        for path in self.state.iterdir():
            if not path.name.endswith('.hash'):
                path.write_text('broken')
        self.refresh_input()
        self.assertIsNotNone(self.invoke(self.payload()))

    def payload(self):
        self.transcript = self.base / "session.jsonl"
        if not self.transcript.exists():
            self.refresh_input()
        return {"tool_name": "Read", "session_id": "test", "transcript_path": str(self.transcript)}

    def refresh_input(self):
        path = self.base / "session.jsonl"
        old = path.read_text() if path.exists() else ""
        thinking = ("memory workflow portable records research " * 8) + ("new " * len(old))
        path.write_text(json.dumps({"type": "assistant", "message": {"content": [
            {"type": "thinking", "thinking": thinking}]}}) + "\n")

    def test_context_encoding_and_dedup(self):
        output = self.invoke(self.payload())
        self.assertEqual(output["hookEventName"], "PreToolUse")
        self.assertIn('Sample "quoted" context\nsecond line', output["additionalContext"])
        self.assertIsNone(self.invoke(self.payload()))
        self.assertEqual(len(self.calls.read_text().splitlines()), 1)
        # Expired throttle still deduplicates unchanged thinking.
        next(self.state.glob('*.last_fire')).write_text('0')
        self.assertIsNone(self.invoke(self.payload()))

    def test_filtered_tools_and_missing_transcript(self):
        payload = self.payload()
        for tool in ["Write", "Edit", "Bash"]:
            payload["tool_name"] = tool
            self.assertIsNone(self.invoke(payload))
        payload["tool_name"] = "Read"
        payload["transcript_path"] = str(self.base / "missing.jsonl")
        self.assertIsNone(self.invoke(payload))
        self.assertFalse(self.calls.exists())

    def test_broken_ledger_preserves_qmd_result(self):
        db_path = self.base / "invalid.sqlite3"
        db_path.write_bytes(b"not a database")
        self.env["LEDGER_DB"] = str(db_path)
        output = self.invoke(self.payload())
        self.assertIn('Sample "quoted" context', output["additionalContext"])

    def test_ledger_only_recall(self):
        self.result.write_text("No results found.")
        db_path = self.base / "ledger.sqlite3"
        with sqlite3.connect(db_path) as db:
            db.execute("CREATE VIRTUAL TABLE fts_unified USING fts5(domain, timestamp, content_text)")
            text = "memory workflow portable records research " * 100
            db.execute("INSERT INTO fts_unified VALUES (?, ?, ?)", ("example", "2026.10.05", text))
        self.env["LEDGER_DB"] = str(db_path)
        self.env["QMD_BIN"] = str(self.base / "missing-command")
        output = self.invoke(self.payload())
        self.assertIn("Past Session History", output["additionalContext"])
        self.assertIn("[example]", output["additionalContext"])

if __name__ == "__main__":
    unittest.main(verbosity=2)
