# /mascot-subagent-test - サブエージェントマスコット統合テスト

子マスコットのスポーン → サブエージェントTTS → ディスミスの一連フローをテストする。

## Usage

```
/mascot-subagent-test              # 子マスコット1体でテスト
/mascot-subagent-test --parallel   # 2体並列テスト
```

## 前提

- マスコットアプリが起動中であること（`/mascot-run` で起動）
- COEIROINK v2 は任意（未起動でもシグナルテストは可能）

## 実行手順

### Step 1: マスコット起動確認

```bash
pgrep -f "utsutsu_code" > /dev/null 2>&1 && echo "RUNNING" || echo "NOT_RUNNING"
```

`NOT_RUNNING` → 「`/mascot-run` で先にマスコットを起動してください」と案内して終了。

### Step 2: 子マスコットをスポーン

```python
python3 -c "
import json, os, uuid
from pathlib import Path

parent_dir = os.path.expanduser('~/.claude/utsutsu-code')
task_id = uuid.uuid4().hex[:8]
signal_dir = os.path.join(parent_dir, f'task-test-{task_id}')

# Clean stale state
os.makedirs(signal_dir, exist_ok=True)
dismiss = os.path.join(signal_dir, 'mascot_dismiss')
if os.path.exists(dismiss):
    os.remove(dismiss)

# Write spawn signal
spawn = os.path.join(parent_dir, 'spawn_child')
Path(spawn).write_text(json.dumps({
    'signal_dir': signal_dir,
    'model': 'blend_shape_mini',
    'wander': True,
}), encoding='utf-8')

print(f'SIGNAL_DIR={signal_dir}')
print(f'TASK_ID={task_id}')
"
```

出力から `SIGNAL_DIR` を取得する。3秒待って子マスコットが起動したことを確認:

```bash
sleep 3 && pgrep -f "utsutsu_code" | wc -l
```

2以上なら成功。

### Step 3: サブエージェントからTTS送信

Task tool でサブエージェントを起動し、子マスコットにTTSを送らせる。
`SIGNAL_DIR` は Step 2 で取得した値に置き換える。

**方法A: Task tool (推奨)**

```
Task(
  description="Mascot TTS test",
  subagent_type="general-purpose",
  prompt="Run these bash commands in sequence and report results:
1. echo 'サブエージェント開始'
2. python3 ~/.claude/hooks/mascot_tts.py --signal-dir SIGNAL_DIR --emotion Gentle 'サブエージェントです'
3. sleep 3
4. python3 ~/.claude/hooks/mascot_tts.py --signal-dir SIGNAL_DIR --emotion Joy 'テスト完了です'"
)
```

**方法B: フォールバック（Task tool がエラーの場合）**

Task tool が "Agent type 'undefined'" エラーを返す場合は、直接 Bash で実行する:

```bash
echo 'サブエージェント開始'
python3 ~/.claude/hooks/mascot_tts.py --signal-dir SIGNAL_DIR --emotion Gentle 'サブエージェントです'
sleep 3
python3 ~/.claude/hooks/mascot_tts.py --signal-dir SIGNAL_DIR --emotion Joy 'テスト完了です'
```

※ フォールバックではサブエージェント分離のテストにはならないが、TTS→子マスコット表示のフローは検証できる。

### Step 4: 子マスコットをディスミス

```bash
touch SIGNAL_DIR/mascot_dismiss
```

3秒待って子プロセスが終了したことを確認:

```bash
sleep 3 && pgrep -f "utsutsu_code" | wc -l
```

1に戻れば成功。

### Step 5: クリーンアップ

```bash
rm -rf SIGNAL_DIR
```

### --parallel の場合

Step 2〜4 を2体分実行する。それぞれ異なる `SIGNAL_DIR` を使用。
2体のサブエージェントは **並列で** Task tool を呼び出す（同一メッセージ内で2つのTask呼び出し）。

```
Task #0: --signal-dir task-test-{id0}/ --emotion Gentle "ゼロ号機です"
Task #1: --signal-dir task-test-{id1}/ --emotion Gentle "壱号機です"
```

## 確認ポイント

| 項目 | 期待値 |
|------|--------|
| 子マスコットが画面下を徘徊する | 段ボール持ち、小さいサイズ |
| 顔の向きと歩く方向が一致する | 左に歩く→左を向く |
| サブエージェントTTS → 子マスコットだけに表示 | 親マスコットには表示されない |
| ディスミス → ポップアニメーションで消える | プロセスも終了する |
| --parallel: 2体が同時に画面上にいる | 別々の位置で徘徊 |

## 結果報告

テスト完了後、以下の形式で報告:

```
サブエージェントマスコットテスト:
- スポーン: OK / NG
- TTS送信: OK / NG（エンジン: coeiroink / none）
- ディスミス: OK / NG
- プロセス数: 開始前 X → スポーン後 Y → ディスミス後 Z
```
