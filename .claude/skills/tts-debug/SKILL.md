---
name: tts-debug
description: TTS engine status check, speaker test, and troubleshooting
user_invocable: true
---

# /tts-debug - TTS Engine Management

## Overview

Check TTS engine status, list available speakers, test synthesis, and troubleshoot issues.
Supports COEIROINK v2 (port 50032) and VOICEVOX (port 50021).

## Steps

### Step 1: Engine Status Check

```bash
# Check COEIROINK v2
curl -s --connect-timeout 2 http://localhost:50032/v1/speakers > /dev/null && echo "COEIROINK v2 is running" || echo "COEIROINK v2 is NOT running"

# Check VOICEVOX
curl -s --connect-timeout 2 http://localhost:50021/speakers > /dev/null && echo "VOICEVOX is running" || echo "VOICEVOX is NOT running"
```

### Step 2: List Speakers

For COEIROINK v2:
```bash
curl -s http://localhost:50032/v1/speakers | python3 -c "
import json, sys
speakers = json.load(sys.stdin)
for s in speakers:
    styles = ', '.join(f'{st[\"styleName\"]}(id={st[\"styleId\"]})' for st in s['styles'])
    print(f'  {s[\"speakerName\"]} (uuid={s[\"speakerUuid\"]}): {styles}')
"
```

For VOICEVOX:
```bash
curl -s http://localhost:50021/speakers | python3 -c "
import json, sys
speakers = json.load(sys.stdin)
for s in speakers:
    styles = ', '.join(f'{st[\"name\"]}(id={st[\"id\"]})' for st in s['styles'])
    print(f'  {s[\"name\"]}: {styles}')
"
```

### Step 3: TTS Test

Test via the project's TTS dispatcher:

```bash
# Auto-detect engine
python3 .claude/hooks/mascot_tts.py --emotion Joy "テストです"

# Force specific engine
TTS_ENGINE=coeiroink python3 .claude/hooks/mascot_tts.py --emotion Gentle "テストです"
TTS_ENGINE=voicevox python3 .claude/hooks/mascot_tts.py --emotion Gentle "テストです"
TTS_ENGINE=none python3 .claude/hooks/mascot_tts.py --emotion Gentle "テストです"
```

### Step 4: Troubleshooting

1. **TTS engine not running**
   - COEIROINK: Launch COEIROINKv2.app (default port 50032)
   - VOICEVOX: Launch VOICEVOX.app (default port 50021)

2. **Speaker not found**
   - Check speaker list in Step 2
   - Configure `speaker_name` in `.claude/hooks/tts_config.toml`

3. **No audio playback**
   - macOS: Check volume settings, verify `afplay` is available: `which afplay`
   - Windows: `mascot_tts.py` uses PowerShell `System.Media.SoundPlayer` (no extra tools needed). Check volume settings

4. **Check logs**
   ```bash
   cat ~/.claude/logs/mascot_tts.log
   ```

5. **Signal file not working**
   - Check signal directory exists: `ls ~/.claude/utsutsu-code/`
   - Verify mascot app is polling: the app reads `~/.claude/utsutsu-code/mascot_speaking`

## Notes

- Falls back to platform-native notification when no TTS engine is available (osascript on macOS, PowerShell balloon tip on Windows)
- Uses stdlib only (no pip dependencies)
- Supports auto-detection: tries COEIROINK → VOICEVOX → signal-only
- Configure via `.claude/hooks/tts_config.toml` or `TTS_ENGINE` / `TTS_SPEAKER` env vars

## Related Skills

- `/tsukuyomi-setup` — Full setup
- `/tsukuyomi-cleanup` — Cleanup
- `/mascot-run` — Launch mascot app
- `/tts` — Manual TTS execution
