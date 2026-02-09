# CLAUDE.md - utsutsu-code

Desktop mascot with lip-sync animation for AI coding assistants.

## TTS Notification

Announce work start and completion via the mascot TTS dispatcher:

```bash
python3 mascot/hooks/mascot_tts.py --emotion KEY "summary (30 chars max)"
```

Emotion keys are defined in `mascot/emotions.toml`:
- **Gentle** = normal (greetings, explanations)
- **Joy** = success (tests passed, task completed)
- **Blush** = shy (being praised, minor mistakes)
- **Trouble** = error (build failed, test failed)
- **Singing** = celebration (releases, milestones)

Rules:
- Start and end of each task
- No ASCII alphabet in messages — use Japanese or katakana (commit → コミット, README → リードミー)
- 30 characters max

## Signal Files

Signal files live under `~/.claude/utsutsu-code/`:
- `mascot_speaking` — TTS hook writes, mascot reads (JSON with message + emotion)
- `mascot_listening` — voice input writes, mascot reads

