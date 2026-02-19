---
name: mascot-run
description: マスコットアプリとCOEIROINKの起動（セットアップ済み前提）
user_invocable: true
---

# /mascot-run - マスコットアプリ起動

セットアップ済みのマスコットアプリを起動する。
`/tsukuyomi-setup` が完了済みであることが前提。未セットアップの場合は `/tsukuyomi-setup` を案内する。

## Usage

```
/mascot-run              # マスコットを起動
/mascot-run --no-tts     # COEIROINK チェックをスキップして起動
```

## プラットフォーム判定

```bash
case "$(uname -s)" in
  MINGW*|MSYS*|CYGWIN*) echo "WINDOWS" ;;
  Darwin*)              echo "MACOS" ;;
  *)                    echo "LINUX" ;;
esac
```

## 実行手順

### Step 1: マスコットが既に起動しているか確認

**macOS / Linux:**
```bash
pgrep -f "utsutsu_code" && echo "ALREADY_RUNNING" || echo "NOT_RUNNING"
```

**Windows:**
```bash
powershell -c "if (Get-Process mascot -ErrorAction SilentlyContinue) { 'ALREADY_RUNNING' } else { 'NOT_RUNNING' }"
```

`ALREADY_RUNNING` の場合 → 「マスコットは既に起動しています」と伝えて終了。再起動したい場合は `/tsukuyomi-cleanup process` で停止してから再実行を案内する。

### Step 2: COEIROINK v2 の起動確認

`--no-tts` 引数がある場合はこのステップをスキップする。

```bash
curl -s --connect-timeout 2 http://localhost:50032/v1/speakers > /dev/null 2>&1 \
  && echo "COEIROINK_RUNNING" || echo "COEIROINK_NOT_RUNNING"
```

`COEIROINK_NOT_RUNNING` の場合:

**macOS:**
```bash
# アプリがインストールされているか確認
ls /Applications/COEIROINKv2.app > /dev/null 2>&1 && echo "INSTALLED" || echo "NOT_INSTALLED"
```

- **インストール済み** → 「COEIROINK v2 を起動してください」と案内。起動後に再度このスキルを実行するよう伝える
- **未インストール** → 「COEIROINK v2 がインストールされていません。`/tsukuyomi-setup` でセットアップしてください」と案内

**Windows:** ポートチェックのみ。未起動なら「COEIROINK v2 を起動してください」と案内。

COEIROINK なしでもマスコット自体は動作する（口パク・感情表現は動くが音声なし）。ユーザーが「音声なしでいい」と言った場合は次のステップに進む。

### Step 3: セットアップ状態の簡易チェック

**macOS / Linux:**
```bash
# モデルまたはフォールバック画像があるか
(ls mascot/assets/models/blend_shape/*.inp 2>/dev/null || \
 ls mascot/assets/models/parts/*.inp 2>/dev/null || \
 ls mascot/assets/fallback/mouth_open.png 2>/dev/null) \
  && echo "ASSETS_OK" || echo "NO_ASSETS"
```

`NO_ASSETS` の場合 → 「モデルとフォールバック画像がありません。`/tsukuyomi-setup` を先に実行してください」と案内して終了。

**Windows:** リリース exe にアセットがバンドル済みのため、このチェックはスキップ。

### Step 4: マスコットアプリを起動

**macOS:**

バックグラウンドで `flutter run` を実行する。ターミナルをブロックしないように `&` で起動:
```bash
cd mascot && flutter run -d macos &
```

起動メッセージを待ち、アプリウィンドウが表示されたことを確認する。

**Windows:**

リリース exe を使う。Flutter ビルド環境は不要。

1. exe の場所を確認する:
```bash
# よくある配置先
ls ~/Desktop/utsutsu-code-windows/utsutsu_code.exe 2>/dev/null || \
ls ~/Downloads/utsutsu-code-windows/utsutsu_code.exe 2>/dev/null || \
echo "EXE_NOT_FOUND"
```

2. `EXE_NOT_FOUND` の場合 → GitHub Releases からのダウンロードを案内:
```bash
python3 .claude/skills/tsukuyomi-setup/setup_helper.py check-release
```
リリースページ URL をブラウザで開く: `start <URL>`

3. exe が見つかった場合 → 起動:
```bash
# パスは実際の場所に置き換える
start "" "<exe_path>"
```

**Linux:**
```bash
cd mascot && flutter run -d linux &
```

### Step 5: 起動確認

マスコットが画面に表示されるまで数秒待つ。

**macOS / Linux:**
```bash
sleep 5 && pgrep -f "utsutsu_code" && echo "LAUNCH_OK" || echo "LAUNCH_FAILED"
```

**Windows:**
```bash
powershell -c "Start-Sleep 5; if (Get-Process mascot -ErrorAction SilentlyContinue) { 'LAUNCH_OK' } else { 'LAUNCH_FAILED' }"
```

`LAUNCH_OK` の場合 → 「マスコットが起動しました」と報告して終了。テストは行わない（テストしたい場合は `/mascot-test` を案内）。

`LAUNCH_FAILED` の場合 → トラブルシューティングを案内:
- 「`/tts-debug` でTTSエンジンの状態を確認してください」
- 「`flutter doctor` でFlutter環境を確認してください」（macOS/Linux）

## 関連スキル

- `/tsukuyomi-setup` — フルセットアップ（初回）
- `/tsukuyomi-cleanup` — プロセス停止・リソース削除
- `/mascot-test` — 口パク・感情のテスト（TTS不要）
- `/tts-debug` — TTS問題の診断
