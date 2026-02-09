---
name: tsukuyomi-setup
description: つくよみちゃんボイス(COEIROINK v2)セットアップ・テスト・口パク設定
user_invocable: true
---

# /tsukuyomi-setup - つくよみちゃんボイスセットアップ

## 概要

COEIROINK v2 エンジンを使用したつくよみちゃんTTSのセットアップ、テスト、口パクマスコットとの連携設定を行う。

## 前提条件

- COEIROINK v2 (ポート50032)
- Python 3.x
- Flutter SDK (マスコットアプリ用)

## 実行手順

### Step 1: COEIROINK v2 状態確認

```bash
curl -s --connect-timeout 2 http://localhost:50032/v1/speakers > /dev/null 2>&1 \
  && echo "COEIROINK v2 is running" \
  || echo "COEIROINK v2 is NOT running"
```

起動していない場合:
- macOS: COEIROINKv2.app を開く
- デフォルトポート 50032 で起動しているか確認

### Step 2: つくよみちゃんスピーカー確認

```bash
curl -s http://localhost:50032/v1/speakers | python3 -c "
import json, sys
speakers = json.load(sys.stdin)
found = False
for s in speakers:
    if 'つくよみ' in s.get('speakerName', ''):
        styles = ', '.join(f'{st[\"styleName\"]}(id={st[\"styleId\"]})' for st in s['styles'])
        print(f'Found: {s[\"speakerName\"]} (uuid={s[\"speakerUuid\"]})')
        print(f'  Styles: {styles}')
        found = True
if not found:
    print('つくよみちゃん not found. Install voice data in COEIROINK v2.')
    print('Available speakers:')
    for s in speakers:
        print(f'  {s[\"speakerName\"]}')
"
```

つくよみちゃんのデフォルトスタイル:
| スタイル | styleId |
|---------|---------|
| れいせい | 0 |

### Step 3: TTS config 設定

```bash
cat > hooks/tts_config.toml << 'TOML'
# Tsukuyomi via COEIROINK v2
engine = "coeiroink"
speaker_name = "つくよみ"
TOML
```

グローバルhookにも反映:

```bash
cat > ~/.claude/hooks/tts_config.toml << 'TOML'
# Tsukuyomi via COEIROINK v2
engine = "coeiroink"
speaker_name = "つくよみ"
TOML
```

### Step 4: フォールバック画像のセットアップ

```bash
make setup-fallback
```

これにより `assets/fallback/mouth_open.png` と `mouth_closed.png` がダウンロードされる。
kokoro2d モデル (.inp) がない場合、マスコットはこの2枚絵で口パクする。

### Step 5: モデルディレクトリのセットアップ

```bash
make setup-models
```

kokoro2d モデルファイルがある場合:
```bash
cp /path/to/tsukuyomi_blend_shape.inp assets/models/blend_shape/model.inp
# または
cp /path/to/tsukuyomi_parts.inp assets/models/parts/model.inp
```

### Step 6: TTS テスト

```bash
# プロジェクトのディスパッチャ経由
python3 hooks/mascot_tts.py --emotion Gentle "つくよみちゃんのテストです"
python3 hooks/mascot_tts.py --emotion Joy "テスト成功だよ"
python3 hooks/mascot_tts.py --emotion Trouble "テスト失敗だよ"

# グローバルhook経由
python3 ~/.claude/hooks/mascot_tts.py --emotion Gentle "グローバルフックのテスト"
```

各テストで:
- 音声が再生されること
- シグナルファイル `~/.claude/utsutsu-code/mascot_speaking` が一時的に作成されること
- マスコットアプリが起動中なら口パクと吹き出しが表示されること

### Step 7: マスコットアプリ起動テスト

```bash
flutter run -d macos
```

アプリが起動したら、別ターミナルでTTSテスト:
```bash
python3 hooks/mascot_tts.py --emotion Joy "マスコット動いてるよ"
```

確認ポイント:
- 口パク（mouth_open/closed が150ms間隔で切り替わる）
- 吹き出しにメッセージが表示される
- 音声再生終了後に吹き出しがフェードアウトする

### Step 8: settings.json 確認

プロジェクトの `.claude/settings.json`:
```json
{
  "hooks": {
    "Stop": [
      {
        "matcher": "",
        "hooks": [
          {
            "type": "command",
            "command": "python3 hooks/mascot_tts.py --emotion Joy \"タスク完了しました\""
          }
        ]
      }
    ]
  }
}
```

グローバルの `~/.claude/settings.json` にも同様のhookがあるか確認。

## トラブルシューティング

1. **COEIROINK v2 が起動していない**
   - COEIROINKv2.app を起動する
   - ポート確認: `lsof -i :50032`

2. **つくよみちゃんが見つからない**
   - COEIROINK v2 でボイスデータをインストール
   - Step 2 でスピーカー一覧を確認

3. **音声が再生されない**
   - macOS の音量設定を確認
   - `which afplay` で afplay が使えるか確認

4. **マスコットが口パクしない**
   - シグナルディレクトリ確認: `ls ~/.claude/utsutsu-code/`
   - マスコットのポーリング間隔は100ms
   - ログ確認: `cat ~/.claude/logs/mascot_tts.log`

5. **フォールバック画像が表示されない**
   - `ls assets/fallback/` で画像があるか確認
   - なければ `make setup-fallback` を実行

## ファイル一覧

| ファイル | 説明 |
|---------|------|
| `hooks/mascot_tts.py` | 汎用TTSディスパッチャ |
| `hooks/tts_config.toml` | TTS設定（speaker_name等） |
| `hooks/tts_config.example.toml` | 設定例 |
| `emotions.toml` | 感情キー定義 |
| `config/examples/blend_shape.toml` | ブレンドシェイプモデル設定例 |
| `config/examples/parts.toml` | パーツモデル設定例 |
| `assets/fallback/` | フォールバック口パク画像 |
| `assets/models/` | kokoro2dモデルディレクトリ |

## クレジット

COEIROINK v2: つくよみちゃん
