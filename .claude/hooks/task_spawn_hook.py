#!/usr/bin/env python3
"""PreToolUse hook for Task tool.

Spawns a child mascot and injects --signal-dir into the subagent prompt.
Also sends an initial TTS message to the child mascot after a short delay.
"""

import json
import os
import subprocess
import sys
import uuid

def main():
    data = json.load(sys.stdin)

    if data.get("tool_name") != "Task":
        return

    # Check if mascot app is running
    try:
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
    tracking_file = os.path.join(parent_dir, "_active_task_mascots")

    # Create signal dir and clean stale dismiss
    os.makedirs(signal_dir, exist_ok=True)
    dismiss_path = os.path.join(signal_dir, "mascot_dismiss")
    if os.path.exists(dismiss_path):
        os.remove(dismiss_path)

    # Send spawn signal to parent mascot
    spawn_signal = os.path.join(parent_dir, "spawn_child")
    with open(spawn_signal, "w", encoding="utf-8") as f:
        json.dump({
            "signal_dir": signal_dir,
            "model": "blend_shape_mini",
            "wander": True,
        }, f)

    # Track this mascot
    with open(tracking_file, "a", encoding="utf-8") as f:
        f.write(f"{task_id} {signal_dir}\n")

    # Send initial TTS after delay (background, non-blocking)
    tts_script = os.path.expanduser("~/.claude/hooks/mascot_tts.py")
    subprocess.Popen(
        [
            "bash", "-c",
            f'sleep 2 && python3 "{tts_script}" '
            f'--signal-dir "{signal_dir}" '
            f'--emotion Gentle "タスク開始します"',
        ],
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
    )

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

    output = {
        "hookSpecificOutput": {
            "hookEventName": "PreToolUse",
            "permissionDecision": "allow",
            "updatedInput": {
                "prompt": new_prompt,
            },
        }
    }
    json.dump(output, sys.stdout, ensure_ascii=False)


if __name__ == "__main__":
    main()
