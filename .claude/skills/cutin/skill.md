---
name: cutin
description: ソシャゲ風カットイン演出 - 感情に応じたSVG背景付きフルスクリーン演出
user_invocable: true
---

# /cutin - カットイン演出

> **macOS専用** — Windowsでは未テスト。`flutter run -d macos` でのみ動作確認済み。

マスコットのフルスクリーンカットインオーバーレイを発動する。
ソシャゲの必殺技演出のようなドラマチックなアニメーション（SVG背景スライドイン → フラッシュ → キャラスライドイン → テキストフェード → TTS再生 → スライドアウト）。

## Usage

```
/cutin "メッセージ"                          # 感情自動選択
/cutin --emotion Joy "テスト全通過！"         # 感情指定
/cutin --emotion Singing --bg cyber "リリース！"  # 感情＋背景指定
```

引数なしで呼ばれた場合は、直前のコンテキストから適切なメッセージと感情を選ぶ。

## 感情キーと背景の対応

| 感情 | 意味 | 自動選択される背景 |
|------|------|-------------------|
| Gentle | 穏やか | sakura（桜吹雪） |
| Joy | 喜び | sparkle_burst（金色キラキラ） |
| Blush | 照れ | sakura（桜吹雪） |
| Trouble | 困惑 | diagonal_stripes（紫ストライプ） |
| Singing | ノリノリ | sparkle_burst（金色キラキラ） |

## 背景パターン（手動指定用）

| 名前 | 説明 |
|------|------|
| speed_lines | 赤系集中線（デフォルト / 不明な感情） |
| diagonal_stripes | 紫斜めストライプ |
| sparkle_burst | 金色キラキラバースト |
| sakura | ピンク桜吹雪 |
| cyber | サイバーグリッド（青/紫） |

## 実行手順

### Step 1: マスコットの起動確認

```bash
pgrep -f "utsutsu_code" && echo "MASCOT_RUNNING" || echo "MASCOT_NOT_RUNNING"
```

`MASCOT_NOT_RUNNING` の場合 → 「マスコットが起動していません。`/mascot-run` で起動してください」と案内して終了。

### Step 2: 引数の解析

- `--emotion KEY` → 感情を指定（Gentle / Joy / Blush / Trouble / Singing）
- `--bg NAME` または `--background NAME` → 背景を手動指定（speed_lines / diagonal_stripes / sparkle_burst / sakura / cyber）
- それ以外の引数 → メッセージとして結合

引数なしの場合:
- 直前の会話コンテキストからメッセージと感情を推測する
- 例: テスト成功後 → `emotion=Joy, message="テスト全部通過！"`
- 例: リリース時 → `emotion=Singing, message="リリースおめでとう！"`

### Step 3: シグナルファイルの書き込み

`~/.claude/utsutsu-code/cutin` にJSONを書き込む。マスコットがファイル監視で検出し、サブプロセスとしてカットインを起動する。

```bash
python3 -c "
import json, os, sys

home = os.environ.get('HOME') or os.environ.get('USERPROFILE')
signal_dir = f'{home}/.claude/utsutsu-code'
signal_path = f'{signal_dir}/cutin'
os.makedirs(signal_dir, exist_ok=True)

signal = json.dumps({
    'message': MESSAGE,
    'emotion': EMOTION,
    'background': BACKGROUND
})
with open(signal_path, 'w', encoding='utf-8') as f:
    f.write(signal)
print(f'Cut-in triggered: {EMOTION} / {MESSAGE}')
"
```

MESSAGE, EMOTION, BACKGROUND は引数から置き換えること。
background が未指定の場合はキーを省略する（マスコット側で感情から自動選択される）。

### Step 4: 発動確認

シグナルファイルが処理されるのを待つ（マスコットが `_processing` にリネームする）:

```bash
sleep 2
ls ~/.claude/utsutsu-code/cutin 2>/dev/null && echo "SIGNAL_PENDING" || echo "SIGNAL_CONSUMED"
```

- `SIGNAL_CONSUMED` → 「カットイン発動しました」と報告
- `SIGNAL_PENDING` → 「シグナルがまだ処理されていません。マスコットが正常に動作しているか確認してください」と案内

## ルール

- メッセージにアルファベットは使わず、日本語かカタカナ英語で書く
- メッセージは30文字以内
- カットイン中はマスコットがTTSも再生する（COEIROINK起動時）
- 短時間に連続して呼ばない（前のカットインが終わるまで待つ）

## 使い分け: /tts vs /cutin

| | /tts | /cutin |
|---|------|--------|
| 演出 | 吹き出し + 口パク | フルスクリーン + SVG背景 + スライドイン |
| 用途 | 通常の通知・報告 | 特別なイベント・お祝い |
| 頻度 | 高（作業開始/完了） | 低（マイルストーン・リリース） |

## 関連スキル

- `/tts` — 通常のTTS読み上げ
- `/mascot-run` — マスコット起動
- `/mascot-test` — 表示テスト
