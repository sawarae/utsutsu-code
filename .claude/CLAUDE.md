# CLAUDE.md - utsutsu-code

Desktop mascot with lip-sync animation for AI coding assistants.

## つくよみちゃんTTS通知

作業開始時と作業完了時に `python3 ~/.claude/hooks/mascot_tts.py --emotion KEY "要約(30文字以内)"` でつくよみちゃんに読み上げさせる。
感情キーは `mascot/config/emotions.toml` を参照。状況に合った感情を選ぶこと。

- **開始時**: `python3 ~/.claude/hooks/mascot_tts.py --emotion Gentle "透過の修正を始めます"`
- **完了時**: `python3 ~/.claude/hooks/mascot_tts.py --emotion Joy "コミット完了しました"`
- **エラー時**: `python3 ~/.claude/hooks/mascot_tts.py --emotion Trouble "ビルドに失敗しました"`
- COEIROINK v2未起動時はosascript通知にフォールバック
- 要約にアルファベットは使わず、日本語かカタカナ英語で書く（例: commit→コミット、README→リードミー）
- 30文字以内

感情キー（`mascot/config/emotions.toml`）:
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
| `.claude/hooks/mascot_tts.py` | `~/.claude/hooks/mascot_tts.py` |
| `.claude/skills/*` | `~/.claude/skills/*` |

セットアップ: `/tsukuyomi-setup` / クリーンアップ: `/tsukuyomi-cleanup`

## Testing Protocol

`/develop` の Phase 4 で必ず以下のテストを実行すること。PR前に全レベルをクリアしないとマージ禁止。

### L1: ユニットテスト

```bash
cd mascot && flutter test
```

- 新機能には対応するユニットテストを追加する
- `test/widget_test.dart` にテストケースを追記
- 物理演算（衝突判定、慣性、バウンド）もユニットテスト対象

### L2: ビルド確認

```bash
cd mascot && flutter build macos
```

- コンパイルエラーがないことを確認

### L3: 実行テスト（UI変更時は必須）

以下のいずれかに該当する変更は **L3 必須**:
- ウィジェット (`mascot_widget.dart`)
- アニメーション（口パク、バウンス、スキッシュ）
- 物理演算（`wander_controller.dart` — 移動、衝突、ドラッグ、慣性）
- ウィンドウ管理（透過、位置、サイズ）
- 表情・感情表現 (`expression_service.dart`)

**手順:**

1. アプリ起動: `/mascot-run`
2. 感情テスト: `/mascot-test` — 5感情の口パク・吹き出し・表情を目視確認
3. 変更した機能の動作確認（例: 衝突判定なら子マスコットを複数起動して重なりを確認）
4. 結果をPR本文に記載する（「L3実行テスト: 口パク確認済み、衝突判定確認済み」等）

**L3 をスキップしたら `/learn` で記録すること。**

### テスト対象の判定

| 変更箇所 | L1 | L2 | L3 |
|----------|----|----|-----|
| `mascot_controller.dart` | 必須 | 必須 | 推奨 |
| `mascot_widget.dart` | 必須 | 必須 | **必須** |
| `wander_controller.dart` | 必須 | 必須 | **必須** |
| `expression_service.dart` | 必須 | 必須 | **必須** |
| `model_config.dart` | 必須 | 必須 | 推奨 |
| `toml_parser.dart` | 必須 | 必須 | 不要 |
| `tts_service.dart` | 必須 | 必須 | 推奨 |
| `main.dart` (ウィンドウ設定) | 必須 | 必須 | **必須** |
| TOML設定ファイル | 必須 | 必須 | 推奨 |
| スキル・ドキュメントのみ | 不要 | 不要 | 不要 |

