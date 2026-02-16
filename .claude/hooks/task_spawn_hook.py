#!/usr/bin/env python3
"""PreToolUse hook for Task tool.

Spawns a child mascot and injects --signal-dir into the subagent prompt.
The parent mascot handles dir creation, model selection, TTS, and cleanup.
"""

import json
import os
import sys
import uuid


def main():
    data = json.load(sys.stdin)

    if data.get("tool_name") != "Task":
        return

    tool_input = data.get("tool_input", {})

    # Check if mascot app is running
    try:
        import subprocess
        result = subprocess.run(
            ["pgrep", "-f", "utsutsu_code"],
            capture_output=True, timeout=2,
        )
        if result.returncode != 0:
            return
    except Exception:
        return

    prompt = tool_input.get("prompt", "")

    parent_dir = os.path.expanduser("~/.claude/utsutsu-code")
    task_id = uuid.uuid4().hex[:8]
    signal_dir = os.path.join(parent_dir, f"task-{task_id}")

    # Spawn signal: envelope format v1 (parent decides policy)
    spawn_signal = os.path.join(parent_dir, "spawn_child")
    with open(spawn_signal, "w", encoding="utf-8") as f:
        json.dump({
            "version": "1",
            "type": "mascot.spawn",
            "payload": {"task_id": task_id},
        }, f)

    # Inject --signal-dir into the prompt (compact to reduce token overhead)
    inject = (
        f"\n\n---\nMascot TTS: `python3 ~/.claude/hooks/mascot_tts.py"
        f" --signal-dir {signal_dir}"
        ' --emotion KEY "msg"`\n'
        "Keys: Gentle/Joy/Trouble. Call at start+end. 30字以内、日本語で。"
    )

    new_prompt = prompt + inject

    # Preserve all original tool input (subagent_type, description, model, etc.)
    # and only override prompt. Returning only {prompt} would drop subagent_type,
    # causing "Agent type 'undefined'" errors.
    tool_input = data.get("tool_input", {})
    tool_input["prompt"] = new_prompt

    output = {
        "hookSpecificOutput": {
            "hookEventName": "PreToolUse",
            "permissionDecision": "allow",
            "updatedInput": tool_input,
        }
    }
    json.dump(output, sys.stdout, ensure_ascii=False)


if __name__ == "__main__":
    main()
