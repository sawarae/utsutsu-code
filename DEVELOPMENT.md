# 開発ガイド

## 機能

- **utsutsu2dレンダリング**: `.inp`パペットモデルの読み込み（ブレンドシェイプ/パーツベースアニメーション対応）
- **口パク**: シグナルファイル(`~/.claude/utsutsu-code/mascot_speaking`)駆動のマウスアニメーション
- **感情システム**: 5種類の感情（Gentle, Joy, Blush, Trouble, Singing）をモデルごとにパラメータマッピング
- **汎用TTS**: COEIROINK / VOICEVOX / シグナルのみモードに対応するプラグイン式TTSディスパッチャ
- **透過ウィンドウ**: 透明ピクセルのクリックスルー、ネイティブウィンドウドラッグ
- **設定ドリブン**: 全モデルパラメータをTOMLファイルで外部化



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
5. `cd mascot && MASCOT_MODEL=your_character flutter run -d macos` (macOS) または `flutter run -d windows` (Windows) で起動

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
    MainFlutterWindow.swift  # 透過、クリックスルー、ネイティブドラッグ (macOS)
  windows/runner/
    flutter_window.cpp/.h    # 透過、クリックスルー、ネイティブドラッグ (Windows)
    win32_window.cpp/.h      # ボーダーレスウィンドウ (Windows)
.claude/
  hooks/
    mascot_tts.py          # 汎用TTSディスパッチャ
    tts_config.example.toml
  skills/                  # Claude Codeスキル定義
README.md
```

## Windows 開発

### 前提条件

- Flutter SDK 3.10+
- Visual Studio 2022 (C++ デスクトップ開発ワークロード)
- Python 3

### 起動

```bash
cd mascot && flutter run -d windows
```

### ネイティブ実装

Windows版の透過ウィンドウは `mascot/windows/runner/` で実装:

- **flutter_window.cpp**: DWM透過設定、50msポーリングによるクリックスルー判定（`PrintWindow` + DIBセクションでアルファ値を読み取り）、ネイティブドラッグ
- **win32_window.cpp**: `WS_POPUP` + `WS_EX_LAYERED` によるボーダーレス透過ウィンドウ

### COEIROINK / VOICEVOX

Windows版でも macOS と同じく COEIROINK v2 または VOICEVOX を使用可能。
音声再生は PowerShell 経由で `System.Media.SoundPlayer` を使用。

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

## CI / リリース

### GitHub Actions (`release-windows.yml`)

`v*` タグの push で Windows ビルドと GitHub Release 作成を自動実行する。

**トリガー:**
- `v*` タグ push → ビルド + GitHub Release 作成
- `workflow_dispatch` → ビルド + artifact のみ（手動テスト用）

**ステップ:**
1. Flutter セットアップ (3.38.x, キャッシュ有効)
2. `flutter pub get`
3. `gh release download` でモデルファイル (.inp) を取得
4. `flutter build windows --release`
5. モデルファイルをビルド出力にコピー
6. `Compress-Archive` で zip 作成
7. `upload-artifact` で成果物を保存
8. タグ push 時のみ `gh release create --generate-notes`

**リリース手順:**

```bash
git tag v0.xx
git push origin v0.xx
```

成果物は https://github.com/sawarae/utsutsu-code/releases に公開される。

## テスト

```bash
cd mascot && flutter test
```
