#!/usr/bin/env bash
# 子マスコット簡易テスト
# Usage: ./test_child.sh [--keep]
#   --keep: ディスミスせず子マスコットを残す
set -eu

PARENT_DIR="$HOME/.claude/utsutsu-code"
TASK_ID="test-$(date +%s)"
SIGNAL_DIR="$PARENT_DIR/task-$TASK_ID"

# 親マスコット起動チェック
if ! pgrep -f "utsutsu_code" > /dev/null 2>&1; then
  echo "ERROR: マスコットが起動していません。/mascot-run で起動してください"
  exit 1
fi

BEFORE=$(pgrep -f "utsutsu_code" | wc -l | tr -d ' ')
echo "=== 子マスコット簡易テスト ==="
echo "プロセス数(開始前): $BEFORE"

# スポーン
echo ""
echo "[1/3] スポーン..."
python3 -c "
import json, os
from pathlib import Path
signal_dir = '$SIGNAL_DIR'
parent_dir = '$PARENT_DIR'
os.makedirs(signal_dir, exist_ok=True)
dismiss = os.path.join(signal_dir, 'mascot_dismiss')
if os.path.exists(dismiss):
    os.remove(dismiss)
spawn = os.path.join(parent_dir, 'spawn_child')
Path(spawn).write_text(json.dumps({'task_id': '$TASK_ID'.replace('task-','')}), encoding='utf-8')
"
sleep 3
AFTER=$(pgrep -f "utsutsu_code" | wc -l | tr -d ' ')
echo "プロセス数(スポーン後): $AFTER"

if [ "$AFTER" -le "$BEFORE" ]; then
  echo "FAIL: 子マスコットが起動しませんでした"
  rm -rf "$SIGNAL_DIR"
  exit 1
fi
echo "OK: 子マスコット起動"

# TTS テスト
echo ""
echo "[2/3] TTS送信..."
python3 ~/.claude/hooks/mascot_tts.py --signal-dir "$SIGNAL_DIR" --emotion Joy "テスト成功" 2>/dev/null \
  && echo "OK: TTS送信完了" || echo "SKIP: TTS未起動"

# --keep なら残す
if [ "${1:-}" = "--keep" ]; then
  echo ""
  echo "=== --keep: 子マスコットを残します ==="
  echo "ディスミスするには: touch $SIGNAL_DIR/mascot_dismiss"
  echo "クリーンアップ:     rm -rf $SIGNAL_DIR"
  exit 0
fi

sleep 2

# ディスミス
echo ""
echo "[3/3] ディスミス..."
touch "$SIGNAL_DIR/mascot_dismiss"
sleep 3
FINAL=$(pgrep -f "utsutsu_code" | wc -l | tr -d ' ')
echo "プロセス数(ディスミス後): $FINAL"

if [ "$FINAL" -lt "$AFTER" ]; then
  echo "OK: ディスミス成功"
else
  echo "WARN: ディスミスが反映されていない可能性あり"
fi

# クリーンアップ
rm -rf "$SIGNAL_DIR"

echo ""
echo "=== 結果 ==="
echo "スポーン:   $BEFORE → $AFTER"
echo "ディスミス: $AFTER → $FINAL"
