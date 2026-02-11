#!/bin/bash
# PreToolUse hook for Task tool
# Delegates to Python for reliable JSON handling.

exec python3 "$(dirname "$0")/task_spawn_hook.py"
