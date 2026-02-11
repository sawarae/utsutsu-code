---
name: mute
description: TTS音声のミュート切り替え（マスコットアニメーションは維持）
user_invocable: true
---

# /mute - TTS Mute Toggle

Toggle TTS audio mute. When muted, mascot animations (lip-sync, expressions) continue but audio playback and platform notifications are suppressed.

## Steps

1. Toggle the mute state file

```bash
python3 -c "
from pathlib import Path
f = Path.home() / '.claude' / 'utsutsu-code' / 'tts_muted'
f.parent.mkdir(parents=True, exist_ok=True)
if f.exists():
    f.unlink()
    print('ミュート解除しました')
else:
    f.touch()
    print('ミュートしました（アニメーションは継続）')
"
```

2. Report current state to the user
