#!/usr/bin/env python3
"""PostToolUse hook for Task tool.

Dismisses the child mascot spawned by the PreToolUse hook.
Uses LIFO order (last spawned = first dismissed).
"""

import json
import os
import sys
from pathlib import Path


def main():
    data = json.load(sys.stdin)

    if data.get("tool_name") != "Task":
        return

    parent_dir = os.path.expanduser("~/.claude/utsutsu-code")
    tracking_file = os.path.join(parent_dir, "_active_task_mascots")

    if not os.path.exists(tracking_file):
        return

    lines = Path(tracking_file).read_text(encoding="utf-8").strip().splitlines()
    if not lines:
        os.remove(tracking_file)
        return

    # Pop last entry (LIFO)
    last_line = lines[-1]
    remaining = lines[:-1]

    parts = last_line.split(maxsplit=1)
    if len(parts) < 2:
        # Malformed line, skip
        Path(tracking_file).write_text(
            "\n".join(remaining) + ("\n" if remaining else ""),
            encoding="utf-8",
        )
        return

    signal_dir = parts[1]

    # Send dismiss signal
    if os.path.isdir(signal_dir):
        Path(os.path.join(signal_dir, "mascot_dismiss")).touch()

    # Update tracking file
    if remaining:
        Path(tracking_file).write_text(
            "\n".join(remaining) + "\n", encoding="utf-8",
        )
    else:
        os.remove(tracking_file)


if __name__ == "__main__":
    main()
