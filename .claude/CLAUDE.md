# CLAUDE.md - utsutsu-code

Desktop mascot with lip-sync animation for AI coding assistants.

## つくよみちゃんTTS通知

作業開始時と作業完了時に `python3 ~/.claude/hooks/mascot_tts.py --emotion KEY "要約(30文字以内)"` でつくよみちゃんに読み上げさせる。
感情キーは `mascot/emotions.toml` を参照。状況に合った感情を選ぶこと。

- **開始時**: `python3 ~/.claude/hooks/mascot_tts.py --emotion Gentle "透過の修正を始めます"`
- **完了時**: `python3 ~/.claude/hooks/mascot_tts.py --emotion Joy "コミット完了しました"`
- **エラー時**: `python3 ~/.claude/hooks/mascot_tts.py --emotion Trouble "ビルドに失敗しました"`
- COEIROINK v2未起動時はosascript通知にフォールバック
- 要約にアルファベットは使わず、日本語かカタカナ英語で書く（例: commit→コミット、README→リードミー）
- 30文字以内

感情キー（`mascot/emotions.toml`）:
- **Gentle** = 穏やか（挨拶、説明、通常の報告）
- **Joy** = 喜び（テスト成功、ビルド成功、タスク完了）
- **Blush** = 照れ（褒められた時、ちょっとした失敗）
- **Trouble** = 困惑（エラー発生、テスト失敗、警告）
- **Singing** = ノリノリ（お祝い、リリース、マイルストーン）

### TTSを呼ぶタイミング

| タイミング | 感情 | 例 |
|-----------|------|-----|
| 作業開始 | Gentle | `"リファクタリングを始めます"` |
| タスク完了 | Joy | `"実装完了しました"` |
| テスト成功 | Joy | `"全テスト通過しました"` |
| エラー発生 | Trouble | `"ビルドに失敗しました"` |
| 褒められた | Blush | `"ありがとうございます"` |
| お祝い | Singing | `"リリースおめでとう"` |

### 自動フック（Stop イベント）

セッション終了時に自動でTTSが発火する（`.claude/settings.json` で設定済み）。
タイムアウトは5000ミリ秒。可用性チェック(1秒) + 音声合成(4秒)。再生はバックグラウンド。

## シグナルファイル

`~/.claude/utsutsu-code/` に置かれる:
- `mascot_speaking` — TTSフックが書き込み、マスコットが読む（JSON: message + emotion）
- `mascot_listening` — 音声入力が書き込み、マスコットが読む

## ファイル配置

正のソースはすべてこのリポジトリ内。`~/.claude/` にはシンボリックリンクを置く。

| リポジトリ（正） | グローバル（リンク） |
|------------------|---------------------|
| `mascot/hooks/mascot_tts.py` | `~/.claude/hooks/mascot_tts.py` |
| `.claude/skills/*` | `~/.claude/skills/*` |

セットアップ: `/tsukuyomi-setup` / クリーンアップ: `/tsukuyomi-cleanup`

