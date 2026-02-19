#!/usr/bin/env python3
"""PostToolUse hook for Task tool.

Dismisses the child mascot by looking up the task_id from a tracking file
written by task_spawn_hook.py (keyed by tool_use_id).
Falls back to extracting task_id from --signal-dir in the prompt.
"""

import json
import os
import re
import sys
from pathlib import Path


def main():
    data = json.load(sys.stdin)

    if data.get("tool_name") != "Task":
        return

    parent_dir = os.path.expanduser("~/.claude/utsutsu-code")
    task_id = None

    # Strategy 1: look up tracking file by tool_use_id
    tool_use_id = data.get("tool_use_id", "")
    if tool_use_id:
        tracking_file = os.path.join(parent_dir, "_tracking", tool_use_id)
        if os.path.isfile(tracking_file):
            task_id = Path(tracking_file).read_text().strip()
            os.remove(tracking_file)

    # Strategy 2: fallback - extract from --signal-dir in prompt
    if not task_id:
        prompt = data.get("tool_input", {}).get("prompt", "")
        match = re.search(r"--signal-dir\s+\S+/task-([a-f0-9]+)", prompt)
        if match:
            task_id = match.group(1)

    if not task_id:
        return

    signal_dir = os.path.join(parent_dir, f"task-{task_id}")

    # Direct dismiss — parent handles cleanup
    if os.path.isdir(signal_dir):
        Path(os.path.join(signal_dir, "mascot_dismiss")).touch()


if __name__ == "__main__":
    main()
