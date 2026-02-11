---
name: tts
description: つくよみちゃんTTS - 感情付きメッセージ読み上げ
user_invocable: true
---

# /tts - Mascot TTS (with emotion)

Have the mascot speak a message with lip-sync animation and emotion expression.

## Usage

```
/tts "message"
/tts --emotion Joy "Test passed!"
```

When called without arguments, automatically select an appropriate message and emotion from context.

## Emotion Keys

See `mascot/config/emotions.toml` for the canonical reference:

| Key | Meaning | When to use |
|-----|---------|-------------|
| Gentle | Calm, gentle | Greetings, explanations, normal reports |
| Joy | Happy, joyful | Test passed, build succeeded, task completed |
| Blush | Shy, bashful | Being praised, reporting minor mistakes |
| Trouble | Troubled, worried | Error occurred, test failed, warning |
| Singing | Fun, excited | Celebration, jokes, completion fanfare |

## Steps

1. Determine message and emotion
   - Use `--emotion KEY` if specified in arguments
   - Otherwise, choose an appropriate emotion from context
   - Message should be 30 characters or less, no ASCII alphabet (use katakana for English words)

2. Execute the command

```bash
python3 ~/.claude/hooks/mascot_tts.py --emotion KEY "message"
```

### Emotion Selection Examples

- Starting work → `--emotion Gentle "リファクタリングを始めます"`
- Test passed → `--emotion Joy "全テスト通過しました"`
- Build error → `--emotion Trouble "ビルドに失敗しました"`
- Task completed → `--emotion Joy "実装完了しました"`
- Being praised → `--emotion Blush "ありがとうございます"`
- Celebration → `--emotion Singing "リリースおめでとう"`

## Rules

- No ASCII alphabet in messages — use Japanese or katakana (e.g. commit → コミット, README → リードミー)
- Messages must be 30 characters or less
- Falls back to macOS notification automatically when no TTS engine is available

## Related Skills

- `/tsukuyomi-setup` — Full setup
- `/tsukuyomi-cleanup` — Cleanup
- `/tts-debug` — Troubleshooting
