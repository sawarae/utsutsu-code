# CLAUDE.md - utsutsu-code

Desktop mascot with lip-sync animation for AI coding assistants.

## TTS Notification

Announce work start and completion via the mascot TTS dispatcher:

```bash
python3 hooks/mascot_tts.py --emotion KEY "summary (30 chars max)"
```

Emotion keys are defined in `emotions.toml`:
- **Gentle** = normal (greetings, explanations)
- **Joy** = success (tests passed, task completed)
- **Blush** = shy (being praised, minor mistakes)
- **Trouble** = error (build failed, test failed)
- **Singing** = celebration (releases, milestones)

Rules:
- Start and end of each task
- No ASCII alphabet in messages — use Japanese or katakana (commit → コミット, README → リードミー)
- 30 characters max

## Development

```bash
# Run tests
flutter test

# Run app
flutter run -d macos

# Set up models
make setup-models
make setup-fallback
```

## Signal Files

Signal files live under `~/.claude/utsutsu-code/`:
- `mascot_speaking` — TTS hook writes, mascot reads (JSON with message + emotion)
- `mascot_listening` — voice input writes, mascot reads

## Architecture

- `lib/mascot_controller.dart` — polls signal files, manages emotion state and mouth animation
- `lib/mascot_widget.dart` — renders kokoro2d puppet or fallback PNG
- `lib/model_config.dart` — TOML-based model configuration with fallback paths
- `hooks/mascot_tts.py` — generic TTS dispatcher (COEIROINK / VOICEVOX / none)
