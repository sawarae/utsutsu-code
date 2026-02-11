---
name: kyuuklarin
description: きゅうくらりんスキルを追加
user_invocable: true
---

# /kyuuklarin - きゅうくらりん

マスコットがきゅうくらりんっぽくくるくる回転して元に戻る楽しいスキル。

## Usage

```
/kyuuklarin
```

## Steps

1. Write the kyuuklarin signal file to trigger the animation

```bash
python3 -c "
from pathlib import Path
signal_dir = Path.home() / '.claude' / 'utsutsu-code'
signal_dir.mkdir(parents=True, exist_ok=True)
signal_path = signal_dir / 'mascot_kyuuklarin'
signal_path.write_text('')
print('きゅうくらりん♪')
"
```

2. Report to the user that the animation was triggered

The mascot will:
- Spin around 2 times with a scaling effect
- Show the Singing expression with "きゅうくらりん♪" message
- Return to normal after ~1.5 seconds
