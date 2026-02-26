#!/bin/bash
# Claude Code hook: Log session activity to session.jsonl
# Used by PostToolUse / Stop hooks for iOS remote viewing
#
# Environment variables set by Claude Code:
#   CLAUDE_TOOL_NAME - Tool that was used (PostToolUse)
#   CLAUDE_TOOL_INPUT - Tool input JSON
#   CLAUDE_SESSION_ID - Session identifier

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
LOGGER="$REPO_ROOT/ios-remote/server/session_logger.py"

if [ ! -f "$LOGGER" ]; then
    exit 0
fi

TOOL_NAME="${CLAUDE_TOOL_NAME:-unknown}"

# Log tool calls
if [ -n "$CLAUDE_TOOL_NAME" ]; then
    # Extract a short summary from tool input
    SUMMARY=""
    if [ -n "$CLAUDE_TOOL_INPUT" ]; then
        # Try to extract key info from JSON input
        SUMMARY=$(echo "$CLAUDE_TOOL_INPUT" | python3 -c "
import sys, json
try:
    d = json.load(sys.stdin)
    if 'command' in d:
        print(f'{d[\"command\"][:200]}')
    elif 'file_path' in d:
        print(f'{d[\"file_path\"]}')
    elif 'pattern' in d:
        print(f'{d[\"pattern\"]}')
    elif 'query' in d:
        print(f'{d[\"query\"]}')
    elif 'prompt' in d:
        print(f'{d[\"prompt\"][:100]}')
    else:
        keys = list(d.keys())[:3]
        print(', '.join(keys))
except:
    pass
" 2>/dev/null)
    fi

    if [ -n "$SUMMARY" ]; then
        CONTENT="[$TOOL_NAME] $SUMMARY" python3 "$LOGGER" --kind tool_call --content-env CONTENT &
    else
        python3 "$LOGGER" --kind tool_call --content "[$TOOL_NAME]" &
    fi
fi
