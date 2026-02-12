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

    prompt = data.get("tool_input", {}).get("prompt", "")

    parent_dir = os.path.expanduser("~/.claude/utsutsu-code")
    task_id = uuid.uuid4().hex[:8]
    signal_dir = os.path.join(parent_dir, f"task-{task_id}")

    # Minimal spawn signal: task_id only (parent decides policy)
    spawn_signal = os.path.join(parent_dir, "spawn_child")
    with open(spawn_signal, "w", encoding="utf-8") as f:
        json.dump({"task_id": task_id}, f)

    # Inject --signal-dir into the prompt
    inject = (
        "\n\n---\n"
        "IMPORTANT: A dedicated mascot has been spawned for this task.\n"
        "Use this TTS command to communicate with your mascot:\n"
        f"  python3 ~/.claude/hooks/mascot_tts.py --signal-dir {signal_dir}"
        ' --emotion KEY "message(30文字以内)"\n'
        "Emotion keys: Gentle(穏やか), Joy(喜び), Blush(照れ), "
        "Trouble(困惑), Singing(ノリノリ)\n"
        "Call TTS at task start (Gentle) and completion (Joy/Trouble).\n"
        "Do NOT use the default TTS command without --signal-dir."
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
