---
name: mascot-test
description: マスコットの口パク・吹き出し・感情表現をテスト（TTS不要）
user_invocable: true
---

# /mascot-test - マスコット表示テスト

シグナルファイルを直接書き込み、マスコットの口パク・吹き出し・感情表現を確認する。
TTS エンジン（COEIROINK/VOICEVOX）が不要なので、表示側だけのテストに使う。

## Usage

```
/mascot-test                    # 全感情を順番にテスト
/mascot-test Joy "やったー"     # 特定の感情でテスト
```

## 実行手順

### 引数ありの場合（単発テスト）

指定された感情とメッセージでシグナルファイルを書き込み、3秒後に削除する:

```bash
python3 -c "
import json, os, time, sys

home = os.environ.get('HOME') or os.environ.get('USERPROFILE')
signal_dir = f'{home}/.claude/utsutsu-code'
signal_path = f'{signal_dir}/mascot_speaking'
os.makedirs(signal_dir, exist_ok=True)

emotion = sys.argv[1] if len(sys.argv) > 1 else 'Gentle'
message = sys.argv[2] if len(sys.argv) > 2 else 'テスト中です'

signal = json.dumps({'message': message, 'emotion': emotion})
with open(signal_path, 'w', encoding='utf-8') as f:
    f.write(signal)
print(f'Signal written: {emotion} / {message}')

time.sleep(3)

os.remove(signal_path)
print('Signal removed')
" EMOTION MESSAGE
```

EMOTION と MESSAGE は引数から置き換えること。

確認ポイント:
- 口パクアニメーション（150ms 間隔で切り替わる）
- 吹き出しにメッセージが表示される
- 感情に応じた表情が変わる
- シグナル削除後にアイドル表情に戻る

### 引数なしの場合（全感情テスト）

5つの感情を順番にテストする。各感情の間に3秒の表示 + 1秒のアイドル復帰を挟む:

```bash
python3 -c "
import json, os, time

home = os.environ.get('HOME') or os.environ.get('USERPROFILE')
signal_dir = f'{home}/.claude/utsutsu-code'
signal_path = f'{signal_dir}/mascot_speaking'
os.makedirs(signal_dir, exist_ok=True)

tests = [
    ('Gentle', 'おだやかな表情です'),
    ('Joy',    'うれしい表情です'),
    ('Blush',  'てれてる表情です'),
    ('Trouble','こまった表情です'),
    ('Singing','のりのり表情です'),
]

for emotion, message in tests:
    print(f'Testing: {emotion} / {message}')
    signal = json.dumps({'message': message, 'emotion': emotion})
    with open(signal_path, 'w', encoding='utf-8') as f:
        f.write(signal)
    time.sleep(3)
    os.remove(signal_path)
    print(f'  -> OK')
    time.sleep(1)

print('All emotions tested!')
"
```

各感情の表示中に以下を目視確認:

| 感情 | 確認ポイント |
|------|-------------|
| Gentle | アイドルと同じ穏やかな表情 + 口パク + 吹き出し |
| Joy | 笑顔の表情 + 口パク + 吹き出し |
| Blush | 照れた表情 + 口パク + 吹き出し |
| Trouble | 困った表情 + 口パク + 吹き出し |
| Singing | ノリノリ表情 + 口パク + 吹き出し |

テスト完了後、結果をユーザーに報告する。
