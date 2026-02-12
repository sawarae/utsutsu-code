#!/usr/bin/env python3
"""PostToolUse hook for Task tool.

Dismisses the child mascot by extracting the task_id from the prompt's
--signal-dir injection (set by task_spawn_hook.py) and writing mascot_dismiss.
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

    # Extract task_id from the --signal-dir path injected by spawn hook
    prompt = data.get("tool_input", {}).get("prompt", "")
    match = re.search(r"--signal-dir\s+\S+/task-([a-f0-9]+)", prompt)
    if not match:
        return  # no-op: mascot was not spawned for this task

    task_id = match.group(1)
    parent_dir = os.path.expanduser("~/.claude/utsutsu-code")
    signal_dir = os.path.join(parent_dir, f"task-{task_id}")

    # Direct dismiss — parent handles cleanup
    if os.path.isdir(signal_dir):
        Path(os.path.join(signal_dir, "mascot_dismiss")).touch()


if __name__ == "__main__":
    main()
