#!/usr/bin/env python3
"""PostToolUse hook for Task tool.

Dismisses the child mascot by looking up the task_id from the
tool_use_id -> task_id mapping file written by task_spawn_hook.py.

Note: PostToolUse does NOT receive the updatedInput from PreToolUse,
so we cannot extract --signal-dir from the prompt. Instead we use
the tool_use_id mapping.
"""

import json
import os
import sys
from pathlib import Path

_DEBUG = os.environ.get("MASCOT_DEBUG") == "1"


def _resolve_agent_home():
    home = os.path.expanduser("~")
    claude = os.path.join(home, ".claude")
    codex = os.path.join(home, ".codex")
    if os.path.isdir(claude):
        return claude
    if os.path.isdir(codex):
        return codex
    return claude


def main():
    data = json.load(sys.stdin)

    agent_home = _resolve_agent_home()
    parent_dir = os.path.join(agent_home, "utsutsu-code")

    if _DEBUG:
        os.makedirs(parent_dir, exist_ok=True)
        path = os.path.join(parent_dir, "_dismiss_debug.json")
        with open(path, "w") as f:
            json.dump(data, f, indent=2, ensure_ascii=False, default=str)

    if data.get("tool_name") != "Task":
        return

    tool_use_id = data.get("tool_use_id", "")
    if not tool_use_id:
        return

    mapping_path = os.path.join(parent_dir, "_task_mappings", tool_use_id)

    if not os.path.exists(mapping_path):
        return  # no-op: mascot was not spawned for this task

    task_id = Path(mapping_path).read_text().strip()

    # Clean up mapping file
    try:
        os.remove(mapping_path)
    except OSError:
        pass
    signal_dir = os.path.join(parent_dir, f"task-{task_id}")

    # Direct dismiss — parent handles cleanup
    if os.path.isdir(signal_dir):
        Path(os.path.join(signal_dir, "mascot_dismiss")).touch()


if __name__ == "__main__":
    main()
