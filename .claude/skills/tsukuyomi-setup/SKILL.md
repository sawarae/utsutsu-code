---
name: tsukuyomi-setup
description: つくよみちゃんボイス(COEIROINK v2)セットアップ・テスト・口パク設定
user_invocable: true
---

# /tsukuyomi-setup - つくよみちゃんボイスセットアップ

## 概要

COEIROINK v2 エンジンを使用したつくよみちゃんTTSのセットアップ、テスト、口パクマスコットとの連携設定を行う。

## プラットフォーム判定

最初にプラットフォームを判定し、以降のコマンドを分岐する:
```bash
case "$(uname -s)" in
  MINGW*|MSYS*|CYGWIN*) echo "WINDOWS" ;;
  Darwin*)              echo "MACOS" ;;
  *)                    echo "LINUX" ;;
esac
```

## 前提条件

- COEIROINK v2 (ポート50032)
- Python 3.x
- Flutter SDK (マスコットアプリ用)

## 実行手順

### Step 0: 前提条件チェック

各ツールがインストールされているか確認する。見つからないものがあれば、ユーザーに「インストールしていますか？」と確認してから次に進む。

**Python 3 チェック:**
```bash
python3 --version 2>/dev/null && echo "OK" || echo "NOT_FOUND"
```
見つからない場合 → ユーザーに「Python 3 がインストールされていないようです。インストールしていますか？」と聞く。

**Flutter チェック:**
```bash
which flutter 2>/dev/null && echo "OK" || echo "NOT_FOUND"
```
見つからない場合 → ユーザーに「Flutter SDK がインストールされていないようです。インストールしていますか？（マスコットアプリのビルドに必要です）」と聞く。
（注: `flutter --version` はSDK初期化で遅いため `which` で存在チェックのみ行う）

**COEIROINK v2 チェック:**

まず起動状態を確認し、次にアプリの存在を確認する:

```bash
# 1. 起動しているか
curl -s --connect-timeout 2 http://localhost:50032/v1/speakers > /dev/null 2>&1 \
  && echo "RUNNING" || echo "NOT_RUNNING"
```

**macOS のみ — アプリ存在チェック:**
```bash
ls /Applications/COEIROINKv2.app > /dev/null 2>&1 \
  && echo "INSTALLED" || echo "NOT_INSTALLED"
```

**Windows:** アプリ存在チェックは不要（インストール先が環境依存のため）。ポートチェックのみで判定する。

- **未インストール / 未起動の場合** → ダウンロードページをブラウザで開き、起動を案内する:
  - **Windows:** `start https://coeiroink.com/download`
  - **macOS:** `open https://coeiroink.com/download`
  - **Linux:** `xdg-open https://coeiroink.com/download`
- **macOS でインストール済みだが未起動の場合** → 「COEIROINK v2 がインストールされていますが起動していません。COEIROINKv2.app を起動してください」と案内する
- **初回起動時に「開発元が検証できません」と表示される場合** → 以下の手順を案内する:
  - **macOS:** 「システム設定 → プライバシーとセキュリティ」を開くと、ブロックされたアプリの横に「このまま開く」ボタンが表示されるのでクリック
  - **Windows:** SmartScreen で「WindowsによってPCが保護されました」と表示されたら、「詳細情報」をクリック →「実行」をクリック

**判定ルール:**
- Python 3 が無い場合: TTSもマスコットも動かないため、インストールを案内して中断
- Flutter が無い場合: マスコットアプリのビルド(Step 7)をスキップ可能。TTS部分のみセットアップを続行するか聞く
- COEIROINK v2 が未起動の場合: 起動を促す

すべての前提条件が揃っていることを確認してから Step 1 に進む。

### Step 1: COEIROINK v2 状態確認

```bash
curl -s --connect-timeout 2 http://localhost:50032/v1/speakers > /dev/null 2>&1 \
  && echo "COEIROINK v2 is running" \
  || echo "COEIROINK v2 is NOT running"
```

起動していない場合:
- macOS: COEIROINKv2.app を開く
- Windows: COEIROINK v2 を起動する
- デフォルトポート 50032 で起動しているか確認

### Step 2: つくよみちゃんスピーカー確認

```bash
python3 .claude/skills/tsukuyomi-setup/setup_helper.py check-speakers
```

つくよみちゃんのデフォルトスタイル:
| スタイル | styleId |
|---------|---------|
| れいせい | 0 |

### Step 3: TTS config 設定

```bash
cat > .claude/hooks/tts_config.toml << 'TOML'
# Tsukuyomi via COEIROINK v2
engine = "coeiroink"
speaker_name = "つくよみ"
TOML
```

### Step 3.5: グローバルフックのデプロイ

`~/.claude/hooks/` にTTSスクリプトと設定を配置する。

**macOS / Linux:** ユーザーに「シンボリックリンクとコピー、どちらにしますか？」と聞く。

**Windows:** シンボリックリンクは権限の問題があるため、コピーを使用する。

**選択肢A: シンボリックリンク（macOS / Linux 推奨）**

リポジトリのファイルを直接参照するため、更新が自動反映される:
```bash
mkdir -p ~/.claude/hooks ~/.claude/skills
# フック
ln -sf "$(pwd)/.claude/hooks/mascot_tts.py" ~/.claude/hooks/mascot_tts.py
ln -sf "$(pwd)/.claude/hooks/tts_config.toml" ~/.claude/hooks/tts_config.toml 2>/dev/null || \
  cp .claude/hooks/tts_config.toml ~/.claude/hooks/tts_config.toml
# スキル
for skill in tts mute; do
  ln -sf "$(pwd)/.claude/skills/$skill" ~/.claude/skills/$skill
done
```

**選択肢B: コピー（Windows はこちらを使用）**

リポジトリに依存しない独立したコピーを作成する:
```bash
mkdir -p ~/.claude/hooks ~/.claude/skills
# フック
cp .claude/hooks/mascot_tts.py ~/.claude/hooks/mascot_tts.py
cp .claude/hooks/tts_config.toml ~/.claude/hooks/tts_config.toml 2>/dev/null || true
# スキル
for skill in tts mute; do
  cp -r ".claude/skills/$skill" ~/.claude/skills/
done
```

**確認:**
```bash
python3 ~/.claude/hooks/mascot_tts.py --emotion Gentle "グローバルフックのテスト"
```

### Step 4: フォールバック画像のセットアップ

**Windows:** リリース exe にアセットがバンドル済みのため、このステップはスキップする。

**macOS / Linux:**

utsutsu2d モデル (.inp) が既にある場合はこのステップをスキップする:
```bash
ls mascot/assets/models/blend_shape/*.inp 2>/dev/null || ls mascot/assets/models/parts/*.inp 2>/dev/null
```

.inp が無い場合のみ、フォールバック用の口パク画像をダウンロードする:
```bash
cd mascot && make setup-fallback
```

これにより `mascot/assets/fallback/mouth_open.png` と `mouth_closed.png` がダウンロードされ、マスコットはこの2枚絵で口パクする。

### Step 5: モデルディレクトリのセットアップ

**Windows:** リリース exe にモデルがバンドル済みのため、このステップはスキップする。

**macOS / Linux（gh CLI あり）:**
```bash
cd mascot && make setup-models
```

**Windows / gh CLI なし:**
```bash
mkdir -p mascot/assets/models/blend_shape mascot/assets/models/parts
cp -n mascot/config/examples/blend_shape.toml mascot/assets/models/blend_shape/emotions.toml 2>/dev/null || true
cp -n mascot/config/examples/parts.toml mascot/assets/models/parts/emotions.toml 2>/dev/null || true
python3 .claude/skills/tsukuyomi-setup/setup_helper.py download-models
```

utsutsu2d モデルファイルがある場合（リネーム不要、`emotions.toml` の `[model] file` でファイル名を指定済み）:
```bash
cp /path/to/tsukuyomi_blend_shape.inp mascot/assets/models/blend_shape/
# または
cp /path/to/tsukuyomi_parts.inp mascot/assets/models/parts/
```

### Step 6: TTS テスト

```bash
# プロジェクトのディスパッチャ経由
python3 .claude/hooks/mascot_tts.py --emotion Gentle "つくよみちゃんのテストです"
python3 .claude/hooks/mascot_tts.py --emotion Joy "テスト成功だよ"

# グローバルhook経由
python3 ~/.claude/hooks/mascot_tts.py --emotion Gentle "グローバルフックのテスト"
```

各テストで:
- 音声が再生されること
- シグナルファイル `~/.claude/utsutsu-code/mascot_speaking` が一時的に作成されること
- マスコットアプリが起動中なら口パクと吹き出しが表示されること

### Step 7: マスコットアプリ起動テスト

**macOS:**
```bash
cd mascot && flutter run -d macos
```

**Windows:**

リリース済みの exe を使用する。Flutter ビルド環境は不要。

1. GitHub Releases からダウンロードを案内する:
```bash
python3 .claude/skills/tsukuyomi-setup/setup_helper.py check-release
```

2. コマンド出力からリリースページURLを取り出し、プラットフォームに応じてブラウザで直接開く（ターミナルの折り返しでURLが壊れるため、テキスト表示ではなくブラウザを開く）:
   - **Windows:** `start <URL>`
   - **macOS:** `open <URL>`
   - **Linux:** `xdg-open <URL>`
3. ブラウザが開いたら、以下の手順を案内する:
   1. Assets セクションの `utsutsu-code-windows.zip` をクリックしてダウンロード
   2. zipを右クリック →「すべて展開」で解凍（ダブルクリックで中身を見るだけでは動かない）
   3. 展開されたフォルダ内の `mascot.exe` をダブルクリックして起動

アプリが起動したら、`/tts マスコット動いてるよ` で口パク・吹き出しの動作確認を案内する。

確認ポイント:
- 口パク（mouth_open/closed が150ms間隔で切り替わる）
- 吹き出しにメッセージが表示される
- 音声再生終了後に吹き出しがフェードアウトする

### Step 8: settings.json 確認

#### グローバル設定（`~/.claude/settings.json`）

Stop hookはグローバル設定に追加する。プロジェクト設定とグローバル設定の両方にStop hookがあると**二重起動**するため、**グローバルにのみ設定**すること。プロジェクト設定（`.claude/settings.json`）に `hooks.Stop` がある場合は削除する。

グローバル設定にStop hookを追加する:
```bash
cat ~/.claude/settings.json
```

`hooks.Stop` セクションが無い、または `osascript` のみの場合は、上記と同じStop hookを追加する。

**注意点:**
- `timeout: 5000` を必ず設定する（TTSがClaude Codeをブロックしないように）
- タイムアウト内訳: 可用性チェック(1秒) + 音声合成(4秒)。再生はバックグラウンド

**Windows のパス解決:**

hook runner は `~` を展開しない。以下の優先順位で対処する:
1. **プロジェクト設定**: `bash -c 'python3 ~/.claude/hooks/mascot_tts.py ...'` でラップ（Git Bash 環境前提）
2. **グローバル設定**: `python3 C:/Users/<username>/.claude/hooks/mascot_tts.py ...` と絶対パスを使う（PowerShell でも Git Bash でも動く）

絶対パスの取得:
```bash
python3 -c "import os; print(os.path.expanduser('~').replace(chr(92), '/'))"
```

### Step 9: グローバル CLAUDE.md の設定

`~/.claude/CLAUDE.md` にTTS指示が無いと、Claude Codeが作業開始・完了時にマスコットを呼ばない。

確認:
```bash
grep -q "mascot_tts.py" ~/.claude/CLAUDE.md 2>/dev/null && echo "OK" || echo "NOT_FOUND"
```

無い場合、以下の内容を `~/.claude/CLAUDE.md` に追記するようユーザーに案内する:

```
+ 作業開始時と作業完了時に `python3 ~/.claude/hooks/mascot_tts.py --emotion KEY "要約(30文字以内)"` でつくよみちゃんに読み上げさせる。感情キーは `mascot/emotions.toml` を参照（Gentle=通常, Joy=成功, Blush=照れ, Trouble=エラー, Singing=お祝い）。例: 開始時 `python3 ~/.claude/hooks/mascot_tts.py --emotion Gentle "透過の修正を始めます"` 、完了時 `python3 ~/.claude/hooks/mascot_tts.py --emotion Joy "コミット完了しました"` 。COEIROINK v2未起動時はosascript通知にフォールバック。要約にアルファベットは使わず、日本語かカタカナ英語で書く（例: commit→コミット、README→リードミー）
```

**重要:** `~/.claude/CLAUDE.md` はユーザーのプライベート設定なので、勝手に書き換えず「この内容を追記してください」と案内する。

## トラブルシューティング

1. **COEIROINK v2 が起動していない**
   - COEIROINK v2 アプリを起動する
   - macOS: `lsof -i :50032`
   - Windows: `netstat -an | findstr 50032`

2. **つくよみちゃんが見つからない**
   - COEIROINK v2 でボイスデータをインストール
   - Step 2 でスピーカー一覧を確認

3. **音声が再生されない**
   - macOS: 音量設定を確認、`which afplay` で afplay が使えるか確認
   - Windows: `mascot_tts.py` が powershell 経由で再生する（追加ツール不要）

4. **マスコットが口パクしない**
   - シグナルディレクトリ確認: `ls ~/.claude/utsutsu-code/`
   - マスコットのポーリング間隔は100ms
   - ログ確認: `cat ~/.claude/logs/mascot_tts.log`

5. **フォールバック画像が表示されない**
   - `ls mascot/assets/fallback/` で画像があるか確認
   - macOS: `cd mascot && make setup-fallback` を実行
   - Windows: Step 4 の curl コマンドを実行

## ファイル配置

正のソースはリポジトリ内。macOS/Linux では `~/.claude/` にシンボリックリンク、Windows ではコピーを置く。

### リポジトリ内（正のソース）

| ファイル | 説明 |
|---------|------|
| `.claude/hooks/mascot_tts.py` | 汎用TTSディスパッチャ |
| `.claude/hooks/tts_config.toml` | TTS設定（speaker_name等） |
| `.claude/hooks/tts_config.example.toml` | 設定例 |
| `mascot/emotions.toml` | 感情キー定義 |
| `mascot/config/examples/blend_shape.toml` | ブレンドシェイプモデル設定例 |
| `mascot/config/examples/parts.toml` | パーツモデル設定例 |
| `mascot/assets/fallback/` | フォールバック口パク画像 |
| `mascot/assets/models/` | utsutsu2dモデルディレクトリ |
| `.claude/skills/` | スキル定義（コミット対象） |

### グローバル（シンボリックリンク / コピー）

| リンク | リンク先 |
|--------|---------|
| `~/.claude/hooks/mascot_tts.py` | → `.claude/hooks/mascot_tts.py` |
| `~/.claude/hooks/tts_config.toml` | → `.claude/hooks/tts_config.toml` |
| `~/.claude/skills/*` | → `.claude/skills/*` |

**Windows の場合:** シンボリックリンクではなくコピーになるため、リポジトリ側を更新した場合は再度 `/tsukuyomi-setup` の Step 3.5 を実行してコピーを更新する。

### Makefile ターゲット（macOS / Linux のみ）

| ターゲット | 内容 |
|-----------|------|
| `make setup` | モデル + フォールバック画像のダウンロード |
| `make clean` | ビルド + シグナル削除（安全） |
| `make clean-assets` | モデル・画像を削除（要 `make setup` で再取得） |
| `make clean-hooks` | グローバルフックを削除（要 `/tsukuyomi-setup` で再作成） |

**Windows:** `make` が使えないため、各ステップの curl/python3 コマンドを直接実行する。

## 関連スキル

- `/tsukuyomi-cleanup` — クリーンアップ
- `/tts-debug` — TTS問題の診断
- `/tts` — TTS手動実行

## クレジット

COEIROINK v2: つくよみちゃん
