#!/usr/bin/env python3
"""PreToolUse hook for Task tool.

Spawns a child mascot and injects --signal-dir into the subagent prompt.
The parent mascot handles dir creation, model selection, TTS, and cleanup.

Uses tool_use_id -> task_id mapping file so PostToolUse dismiss hook can
find the correct task_id (PostToolUse does not receive updatedInput).
"""

import json
import os
import sys
import uuid

_DEBUG = os.environ.get("MASCOT_DEBUG") == "1"


def _debug_dump(parent_dir, filename, data):
    if not _DEBUG:
        return
    path = os.path.join(parent_dir, filename)
    with open(path, "w") as f:
        json.dump(data, f, indent=2, ensure_ascii=False, default=str)


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

    if data.get("tool_name") != "Task":
        return

    tool_input = data.get("tool_input", {})

    # Check if mascot app is running
    try:
        import subprocess
        import platform
        if platform.system() == "Windows":
            # Avoid tasklist /FI — MSYS/Git Bash converts /FI to a path
            result = subprocess.run(
                ["tasklist"],
                capture_output=True, text=True, timeout=2,
            )
            out = result.stdout.lower()
            if "utsutsu_code.exe" not in out and "mascot.exe" not in out:
                return
        else:
            checks = [
                subprocess.run(["pgrep", "-f", "utsutsu_code"], capture_output=True, timeout=2),
                subprocess.run(["pgrep", "-f", "/mascot$"], capture_output=True, timeout=2),
                subprocess.run(["pgrep", "-f", "bundle/mascot"], capture_output=True, timeout=2),
            ]
            if all(r.returncode != 0 for r in checks):
                return
    except Exception:
        return

    prompt = tool_input.get("prompt", "")

    agent_home = _resolve_agent_home()
    parent_dir = os.path.join(agent_home, "utsutsu-code")
    os.makedirs(parent_dir, exist_ok=True)
    task_id = uuid.uuid4().hex[:8]
    signal_dir = os.path.join(parent_dir, f"task-{task_id}")

    _debug_dump(parent_dir, "_spawn_debug.json", data)

    # Save tool_use_id -> task_id mapping for dismiss hook
    tool_use_id = data.get("tool_use_id", "")
    if tool_use_id:
        mapping_dir = os.path.join(parent_dir, "_task_mappings")
        os.makedirs(mapping_dir, exist_ok=True)
        mapping_path = os.path.join(mapping_dir, tool_use_id)
        with open(mapping_path, "w") as f:
            f.write(task_id)

    # Spawn signal: per-task file to avoid overwrite on parallel spawns
    spawn_signal = os.path.join(parent_dir, f"spawn_child_{task_id}")
    with open(spawn_signal, "w", encoding="utf-8") as f:
        json.dump({
            "version": "1",
            "type": "mascot.spawn",
            "payload": {"task_id": task_id},
        }, f)

    # Inject --signal-dir into the prompt (compact to reduce token overhead)
    inject = (
        f"\n\n---\nMascot TTS: `python3 {agent_home}/hooks/mascot_tts.py"
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
