# utsutsu-code (うつつこーど)

AIコーディングアシスタント向けの口パクアニメーション付きデスクトップマスコット。透過・常に最前面・クリックスルー対応のmacOSウィンドウとして動作し、ネイティブドラッグにも対応。

## 機能

- **utsutsu2dレンダリング**: `.inp`パペットモデルの読み込み（ブレンドシェイプ/パーツベースアニメーション対応）
- **口パク**: シグナルファイル(`~/.claude/utsutsu-code/mascot_speaking`)駆動のマウスアニメーション
- **感情システム**: 5種類の感情（Gentle, Joy, Blush, Trouble, Singing）をモデルごとにパラメータマッピング
- **汎用TTS**: COEIROINK / VOICEVOX / シグナルのみモードに対応するプラグイン式TTSディスパッチャ
- **透過ウィンドウ**: 透明ピクセルのクリックスルー、ネイティブウィンドウドラッグ
- **設定ドリブン**: 全モデルパラメータをTOMLファイルで外部化

## クイックスタート

### 前提条件

- Flutter SDK (3.10+)
- macOS

### セットアップ

```bash
cd mascot

# 依存パッケージのインストール
flutter pub get

# モデルディレクトリと設定例のセットアップ
make setup-models

# フォールバックPNG画像をリリースからダウンロード
make setup-fallback

# model.inpファイルを配置
# assets/models/blend_shape/model.inp

# 起動
flutter run -d macos
```

### モデルファイルなしの場合

`make setup-fallback`でダウンロードしたフォールバックPNG画像、またはグレーのプレースホルダーアイコンで起動します。パペットアニメーションには`.inp`モデルファイルが必要です。

## 環境変数

| 変数 | デフォルト | 説明 |
|------|-----------|------|
| `MASCOT_MODEL` | `blend_shape` | `assets/models/`配下のモデルディレクトリ名 |
| `MASCOT_MODELS_DIR` | `assets/models` | モデルディレクトリのベースパス |
| `TTS_ENGINE` | (自動検出) | TTSエンジン: `coeiroink`, `voicevox`, `none` |
| `TTS_SPEAKER` | (最初に見つかったもの) | スピーカー名のサブストリングフィルタ |

## 感情システム

感情は`mascot/emotions.toml`および各モデルの`emotions.toml`で定義:

| キー | 説明 | 用途 |
|------|------|------|
| `Gentle` | 穏やか・優しい | 挨拶、説明、通常の報告 |
| `Joy` | 嬉しい・楽しい | テスト成功、ビルド成功、タスク完了 |
| `Blush` | 恥ずかしい・照れ | 褒められた時、軽いミスの報告 |
| `Trouble` | 困った・心配 | エラー発生、テスト失敗、警告 |
| `Singing` | ワクワク・興奮 | お祝い、ジョーク、完了ファンファーレ |

### シグナルプロトコル

TTSフックが`~/.claude/utsutsu-code/mascot_speaking`にJSONを書き込み:

```json
{"message": "テキスト", "emotion": "Joy"}
```

マスコットコントローラーがこのファイルを100msごとにポーリングし、感情パラメータと口パクアニメーションを適用。

## TTSセットアップ

```bash
# 自動検出（COEIROINK → VOICEVOX → シグナルのみ の順に試行）
python3 .claude/hooks/mascot_tts.py --emotion Joy "テストメッセージ"

# 明示的に設定する場合
cp .claude/hooks/tts_config.example.toml .claude/hooks/tts_config.toml
# tts_config.tomlを編集してエンジンとスピーカーを設定
```

## カスタムキャラクターの追加

1. `mascot/assets/models/your_character/`ディレクトリを作成
2. 設定例をコピー: `cp mascot/config/examples/blend_shape.toml mascot/assets/models/your_character/emotions.toml`
3. `emotions.toml`をモデルのパラメータ名と値に編集
4. ディレクトリに`model.inp`ファイルを配置
5. `cd mascot && MASCOT_MODEL=your_character flutter run -d macos`で起動

## プロジェクト構成

```
mascot/
  lib/
    main.dart              # アプリエントリポイント、ウィンドウ設定
    mascot_widget.dart     # マスコット描画（utsutsu2d + フォールバック）
    mascot_controller.dart # シグナルファイルポーリング、感情状態、口パクアニメーション
    model_config.dart      # TOMLベースのモデル設定
    toml_parser.dart       # 軽量TOMLパーサー
  config/examples/         # モデルタイプ別の感情設定例
  emotions.toml            # 感情キーの正規定義
  macos/Runner/
    MainFlutterWindow.swift  # 透過、クリックスルー、ネイティブドラッグ
.claude/
  hooks/
    mascot_tts.py          # 汎用TTSディスパッチャ
    tts_config.example.toml
  skills/                  # Claude Codeスキル定義
README.md
```

## Claude Codeスキル

プロジェクト内の `.claude/skills/` にClaude Code用スキルが同梱されている。

### `/tsukuyomi-setup` — セットアップ

前提条件チェック → COEIROINK確認 → TTS設定 → グローバルフックデプロイ → モデルダウンロード → TTSテスト → マスコット起動 → settings.json確認 → CLAUDE.md設定案内 の順で実行。

```
/tsukuyomi-setup
```

初回セットアップで行われること:
- `.claude/hooks/mascot_tts.py` を `~/.claude/hooks/` にシンボリックリンク
- スキルを `~/.claude/skills/` にシンボリックリンク
- `~/.claude/settings.json` にStop hook（セッション終了時のTTS通知）を設定
- `~/.claude/CLAUDE.md` にTTS指示の追記を案内

### `/tsukuyomi-cleanup` — クリーンアップ

プロセス停止 → シグナルファイル削除 → ビルド成果物削除 → アセット削除 → グローバルリンク削除 → CLAUDE.md設定削除案内 の順で実行。

```
/tsukuyomi-cleanup
```

### その他のスキル

| スキル | 説明 |
|--------|------|
| `/tts` | 手動でTTSメッセージを送信 |
| `/tts-debug` | TTSエンジンの状態確認・トラブルシューティング |

### Makefileターゲット

```bash
cd mascot
make setup          # モデル + フォールバック画像のダウンロード
make clean          # ビルド + シグナル削除（安全）
make clean-assets   # モデル・画像を削除
make clean-hooks    # グローバルフックのリンク削除
```

## テスト

```bash
cd mascot && flutter test
```

## つくよみちゃんについて

このアプリでは、フリー素材キャラクター「[つくよみちゃん](https://tyc.rei-yumesaki.net/)」（© Rei Yumesaki）を使用しています。

- **素材名:** つくよみちゃん万能立ち絵素材
- **素材制作者:** 花兎\*
- **素材配布URL:** <https://tyc.rei-yumesaki.net/material/illust/>
- **利用規約:** <https://tyc.rei-yumesaki.net/about/terms/>
