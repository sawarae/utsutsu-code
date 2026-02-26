#!/usr/bin/env python3
"""
Claude Code Session Logger Hook

Appends structured JSON lines to ~/.claude/utsutsu-code/session.jsonl.
Called by Claude Code hooks (PostToolUse, Stop, etc.) to record session activity.

Usage:
  python3 session_logger.py --kind tool_call --content "Read file.txt"
  python3 session_logger.py --kind assistant --content "I'll fix the bug now"
  python3 session_logger.py --kind task_complete --content "All tests passed"
  python3 session_logger.py --kind error --content "Build failed"

  # Pipe stdin (for capturing tool output):
  echo "test output" | python3 session_logger.py --kind tool_output --stdin

Kinds:
  assistant     - Claude's text responses
  tool_call     - Tool invocation (Read, Edit, Bash, etc.)
  tool_output   - Tool result / output
  task_complete - Task finished successfully
  error         - Error occurred
  test_result   - Test run result
  session_start - Session began
  session_end   - Session ended
  tts_request   - TTS triggered from iOS
  raw           - Unstructured text
"""

import argparse
import json
import os
import sys
import time
from pathlib import Path

SIGNAL_DIR = Path.home() / ".claude" / "utsutsu-code"
SESSION_LOG = SIGNAL_DIR / "session.jsonl"
MAX_CONTENT_LEN = 4000  # truncate long outputs


def log_entry(kind: str, content: str):
    """Append a JSON line to the session log."""
    SIGNAL_DIR.mkdir(parents=True, exist_ok=True)

    if len(content) > MAX_CONTENT_LEN:
        content = content[:MAX_CONTENT_LEN] + f"\n... (truncated, {len(content)} chars total)"

    entry = {
        "timestamp": time.time(),
        "kind": kind,
        "content": content,
    }

    try:
        with open(SESSION_LOG, "a", encoding="utf-8") as f:
            f.write(json.dumps(entry, ensure_ascii=False) + "\n")
    except Exception as e:
        print(f"session_logger: failed to write: {e}", file=sys.stderr)


def main():
    parser = argparse.ArgumentParser(description="Log Claude Code session activity")
    parser.add_argument("--kind", required=True,
                        choices=["assistant", "tool_call", "tool_output",
                                 "task_complete", "error", "test_result",
                                 "session_start", "session_end",
                                 "tts_request", "raw"],
                        help="Type of session event")
    parser.add_argument("--content", default="", help="Event content text")
    parser.add_argument("--content-env", default="",
                        help="Read content from this environment variable (shell-safe)")
    parser.add_argument("--stdin", action="store_true",
                        help="Read content from stdin instead of --content")
    args = parser.parse_args()

    content = args.content
    if args.content_env:
        content = os.environ.get(args.content_env, "")
    elif args.stdin:
        content = sys.stdin.read()

    if not content.strip():
        return

    log_entry(args.kind, content.strip())


if __name__ == "__main__":
    main()
