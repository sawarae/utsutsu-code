---
name: tsukuyomi-cleanup
description: つくよみちゃんTTS・マスコット関連リソースのクリーンアップ
user_invocable: true
---

# /tsukuyomi-cleanup - つくよみちゃんクリーンアップ

## 概要

マスコットアプリ、TTS関連のプロセス・シグナルファイル・ビルド成果物・グローバルフックを掃除する。

## プラットフォーム判定

最初にプラットフォームを判定し、以降のコマンドを分岐する:
```bash
case "$(uname -s)" in
  MINGW*|MSYS*|CYGWIN*) echo "WINDOWS" ;;
  Darwin*)              echo "MACOS" ;;
  *)                    echo "LINUX" ;;
esac
```

## 引数

- 省略時: ユーザーに何を掃除するか聞く
- `all`: 全項目を実行
- `process`: プロセスのみ停止
- `signal`: シグナルファイルのみ削除
- `build`: ビルド成果物のみ削除
- `hooks`: グローバルフックのみ削除

## 実行手順

### Step 1: マスコットプロセスの停止

実行中のマスコットアプリを確認し、停止するか聞く。

**macOS / Linux:**
```bash
pgrep -f "utsutsu_code" && echo "RUNNING" || echo "NOT_RUNNING"
```

停止する場合:
```bash
pkill -f "utsutsu_code"
```

**Windows:**
```bash
powershell -c "if (Get-Process mascot -ErrorAction SilentlyContinue) { 'RUNNING' } else { 'NOT_RUNNING' }"
```

停止する場合:
```bash
powershell -c "Stop-Process -Name mascot -Force -ErrorAction SilentlyContinue"
```

`flutter run` が動いている場合も確認:

**macOS / Linux:**
```bash
pgrep -f "flutter run" && echo "FLUTTER_RUN_ACTIVE" || echo "NOT_RUNNING"
```

**Windows:**
```bash
powershell -c "if (Get-Process dart -ErrorAction SilentlyContinue) { 'FLUTTER_RUN_ACTIVE' } else { 'NOT_RUNNING' }"
```

停止する場合:
```bash
powershell -c "Stop-Process -Name dart -Force -ErrorAction SilentlyContinue"
```

### Step 2: シグナルファイルの削除

残留したシグナルファイルを掃除する:
```bash
ls ~/.claude/utsutsu-code/mascot_speaking 2>/dev/null && echo "STALE" || echo "CLEAN"
ls ~/.claude/utsutsu-code/mascot_listening 2>/dev/null && echo "STALE" || echo "CLEAN"
```

残留している場合:
```bash
rm -f ~/.claude/utsutsu-code/mascot_speaking
rm -f ~/.claude/utsutsu-code/mascot_listening
```

### Step 3: ビルド成果物の削除

ユーザーに確認してから削除する。

**macOS / Linux:**
```bash
du -sh mascot/build 2>/dev/null || echo "NO_BUILD"
```

**Windows:**
```bash
ls -d mascot/build 2>/dev/null && echo "HAS_BUILD" || echo "NO_BUILD"
```

削除する場合:
```bash
rm -rf mascot/build
```

### Step 4: ダウンロード済みアセットの削除

ユーザーに確認してから削除する（再ダウンロードに `make setup`（macOS）またはスキルの手動コマンド（Windows）が必要になる）:
```bash
ls mascot/assets/models/blend_shape/model.inp 2>/dev/null && echo "HAS_MODEL"
ls mascot/assets/fallback/mouth_open.png 2>/dev/null && echo "HAS_FALLBACK"
```

削除する場合:
```bash
rm -f mascot/assets/models/blend_shape/model.inp
rm -f mascot/assets/models/parts/model.inp
rm -f mascot/assets/fallback/*.png
```

### Step 5: グローバルフック/コピーの削除

`~/.claude/` のフックとスキルを削除する:
```bash
# フック
ls -la ~/.claude/hooks/mascot_tts.py 2>/dev/null
ls -la ~/.claude/hooks/tts_config.toml 2>/dev/null

# スキル
ls -la ~/.claude/skills/ 2>/dev/null
```

削除する場合:
```bash
# フック
rm -f ~/.claude/hooks/mascot_tts.py
rm -f ~/.claude/hooks/tts_config.toml

# スキル（グローバルにコピーされた tts, mute を削除。プロジェクト内の正のソースは残る）
rm -rf ~/.claude/skills/tts
rm -rf ~/.claude/skills/mute
```

**注意:** フック削除でStop hookのTTS通知が動かなくなる。スキル削除で他プロジェクトからの `/tts` `/mute` が使えなくなる。再セットアップには `/tsukuyomi-setup` を使う。

**重要:** グローバルフック削除後、Stop hookがエラーを出し続ける。クリーンアップ完了時に「**Stop hookのエラーを止めるため、Claude Codeを再起動してください**」とユーザーに案内すること。

### Step 6: ローカル設定ファイルの削除

プロジェクト内のTTS設定を削除するか聞く:
```bash
ls .claude/hooks/tts_config.toml 2>/dev/null && echo "EXISTS" || echo "CLEAN"
```

削除する場合:
```bash
rm -f .claude/hooks/tts_config.toml
```

### Step 7: グローバル CLAUDE.md のTTS設定削除

`~/.claude/CLAUDE.md` にTTS指示が残っていると、フック削除後もClaude Codeがマスコットを呼ぼうとしてエラーになる。

確認:
```bash
grep -q "mascot_tts.py" ~/.claude/CLAUDE.md 2>/dev/null && echo "HAS_TTS_CONFIG" || echo "CLEAN"
```

残っている場合 → ユーザーに「`~/.claude/CLAUDE.md` にTTS設定が残っています。`mascot_tts.py` を含む行を削除してください」と案内する。

**重要:** `~/.claude/CLAUDE.md` はユーザーのプライベート設定なので、勝手に書き換えず案内のみ行う。再セットアップ時は `/tsukuyomi-setup` の Step 9 で再追記を案内する。

## Makefile ターゲット（macOS / Linux のみ）

`mascot/Makefile` にクリーンアップターゲットがある。macOS/Linux ではスキル実行時にこれらを使える:

| ターゲット | 内容 |
|-----------|------|
| `make clean` | ビルド + シグナル削除（安全な基本掃除） |
| `make clean-build` | `build/` のみ削除 |
| `make clean-signal` | シグナルファイルのみ削除 |
| `make clean-assets` | モデル・画像を削除（要 `make setup` で再取得） |
| `make clean-hooks` | グローバルフックのリンク削除（要 `/tsukuyomi-setup` で再作成） |

**Windows:** `make` が使えないため、各ステップのコマンドを直接実行する。

## 確認ルール

- 各ステップで削除前に必ずユーザーに確認する（`all` 引数の場合も確認する）
- プロセス停止は特に注意（保存していないデータがある可能性）
- `make clean` は安全。`clean-assets` と `clean-hooks` は再セットアップが必要になるため必ず確認する
- グローバルフック削除時はStop hookのTTS通知が動かなくなることを警告する

## 関連スキル

- `/mascot-run` — マスコットアプリ起動
- `/tsukuyomi-setup` — 再セットアップ
- `/tts-debug` — TTS問題の診断
