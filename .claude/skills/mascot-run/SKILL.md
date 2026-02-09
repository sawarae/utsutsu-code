---
name: mascot-run
description: マスコットアプリ(Flutter macOS)の起動
user_invocable: true
---

# /mascot-run - マスコットアプリ起動

## 概要

Flutter macOS マスコットアプリを起動し、TTS口パク連携を確認する。

## 前提条件

- Flutter SDK
- モデルまたはフォールバック画像（`mascot/assets/`）

## 実行手順

### Step 1: 既存プロセスの確認

既にマスコットアプリが起動していないか確認する:
```bash
pgrep -f "flutter.*run.*macos" > /dev/null 2>&1 && echo "RUNNING" || echo "NOT_RUNNING"
```

起動中の場合 → ユーザーに「マスコットアプリは既に起動しています。再起動しますか？」と確認する。

### Step 2: Flutter SDK チェック

```bash
which flutter 2>/dev/null && echo "OK" || echo "NOT_FOUND"
```

見つからない場合 → 「Flutter SDK がインストールされていないようです。`/tsukuyomi-setup` でセットアップしてください」と案内して中断。

### Step 3: アセット確認

モデルまたはフォールバック画像があるか確認する:
```bash
# utsutsu2d モデル
ls mascot/assets/models/blend_shape/model.inp 2>/dev/null \
  || ls mascot/assets/models/parts/model.inp 2>/dev/null \
  && echo "MODEL_FOUND"

# フォールバック画像
ls mascot/assets/fallback/mouth_open.png 2>/dev/null \
  && echo "FALLBACK_FOUND"
```

- どちらも無い場合 → 「アセットがありません。`cd mascot && make setup` を実行してください」と案内
- フォールバックのみの場合 → そのまま続行（フォールバックモードで動作する）

### Step 4: マスコットアプリ起動

```bash
cd mascot && flutter run -d macos
```

**注意:**
- `flutter run` はフォアグラウンドで実行される（ホットリロード対応）
- バックグラウンド起動したい場合は `cd mascot && flutter run -d macos --release &` を使う
- 起動には初回ビルドで時間がかかる場合がある

### Step 5: 動作確認

アプリが起動したら、TTSテストで口パク連携を確認する:
```bash
python3 ~/.claude/hooks/mascot_tts.py --emotion Joy "マスコット起動したよ"
```

確認ポイント:
- 口パク（mouth_open/closed が150ms間隔で切り替わる）
- 吹き出しにメッセージが表示される
- 音声再生終了後に吹き出しがフェードアウトする

## トラブルシューティング

1. **ビルドエラー**
   - `cd mascot && flutter pub get` で依存関係を再取得
   - `cd mascot && flutter clean && flutter pub get` でクリーンビルド

2. **ウィンドウが表示されない**
   - macOS のセキュリティ設定で透過ウィンドウが許可されているか確認
   - `window_manager` の初期化ログを確認

3. **口パクしない**
   - シグナルファイル確認: `ls ~/.claude/utsutsu-code/mascot_speaking`
   - マスコットのポーリング間隔は100ms
   - `/tts-debug` で TTS エンジンの状態を確認

## 関連スキル

- `/tsukuyomi-setup` — フルセットアップ
- `/tsukuyomi-cleanup` — クリーンアップ
- `/tts` — TTS手動実行
- `/tts-debug` — TTS問題の診断
