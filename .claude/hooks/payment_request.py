#!/usr/bin/env python3
"""Payment request hook for mascot TTS.

Monitors Claude Code usage/limit signals and writes a payment_request
signal file so the mascot can ask the user to upgrade/pay.

This hook is designed to be called from Claude Code's hook system
when usage limits are approaching (e.g., on a "Stop" or "Notification"
event that includes limit information).

Usage:
  python3 .claude/hooks/payment_request.py
  python3 .claude/hooks/payment_request.py --check-percent 80
  python3 .claude/hooks/payment_request.py --message "カスタムメッセージ"
  python3 .claude/hooks/payment_request.py --clear

Environment:
  CLAUDE_USAGE_PERCENT  - Current usage percentage (0-100)
  CLAUDE_USAGE_LIMIT    - Whether limit is approaching ("true"/"false")
"""

import json
import os
import random
import sys
from pathlib import Path


def _resolve_agent_home():
    """Resolve agent home directory with .claude preferred over .codex."""
    home = os.path.expanduser("~")
    claude = os.path.join(home, ".claude")
    codex = os.path.join(home, ".codex")
    if os.path.isdir(claude):
        return claude
    if os.path.isdir(codex):
        return codex
    return claude


AGENT_HOME = _resolve_agent_home()
SIGNAL_DIR = os.path.join(AGENT_HOME, "utsutsu-code")
PAYMENT_REQUEST_FILE = os.path.join(SIGNAL_DIR, "payment_request")

# Default threshold: trigger at 80% usage
DEFAULT_THRESHOLD = 80

PAYMENT_PHRASES = [
    "リミットが近づいてます…課金お願いします！",
    "もうすぐ使えなくなっちゃいます…",
    "あの…課金していただけると嬉しいです…",
    "リミット間近です、プランの確認お願いします！",
    "このままだと止まっちゃいます…！",
]


def write_payment_request(message=None, emotion="Trouble"):
    """Write the payment_request signal file."""
    os.makedirs(SIGNAL_DIR, exist_ok=True)
    if message is None:
        message = random.choice(PAYMENT_PHRASES)
    signal = json.dumps({
        "version": "1",
        "type": "mascot.payment_request",
        "payload": {
            "message": message,
            "emotion": emotion,
        },
    })
    Path(PAYMENT_REQUEST_FILE).write_text(signal, encoding="utf-8")
    return message


def clear_payment_request():
    """Remove the payment_request signal file."""
    try:
        os.unlink(PAYMENT_REQUEST_FILE)
    except OSError:
        pass


def should_trigger(threshold=DEFAULT_THRESHOLD):
    """Check if usage limit conditions are met.

    Returns True if:
    - CLAUDE_USAGE_LIMIT env var is "true", OR
    - CLAUDE_USAGE_PERCENT >= threshold
    """
    limit_flag = os.environ.get("CLAUDE_USAGE_LIMIT", "").lower()
    if limit_flag == "true":
        return True

    try:
        percent = int(os.environ.get("CLAUDE_USAGE_PERCENT", "0"))
        return percent >= threshold
    except (ValueError, TypeError):
        return False


def main():
    argv = sys.argv[1:]
    threshold = DEFAULT_THRESHOLD
    message = None
    clear = False

    i = 0
    while i < len(argv):
        if argv[i] == "--check-percent" and i + 1 < len(argv):
            threshold = int(argv[i + 1])
            i += 2
        elif argv[i] == "--message" and i + 1 < len(argv):
            message = argv[i + 1]
            i += 2
        elif argv[i] == "--clear":
            clear = True
            i += 1
        else:
            # Treat remaining args as message
            message = " ".join(argv[i:])
            break

    if clear:
        clear_payment_request()
        print(json.dumps({"status": "cleared"}))
        return

    # If called with explicit message, always trigger
    if message:
        used_message = write_payment_request(message=message)
        print(json.dumps({"status": "triggered", "message": used_message}))
        return

    # Otherwise, check if we should trigger based on usage
    if should_trigger(threshold):
        used_message = write_payment_request()
        print(json.dumps({"status": "triggered", "message": used_message}))
    else:
        print(json.dumps({"status": "skipped", "reason": "below_threshold"}))


if __name__ == "__main__":
    main()
