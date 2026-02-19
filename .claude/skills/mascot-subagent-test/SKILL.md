---
name: mascot-subagent-test
description: hook経由の子マスコットspawn/dismissテスト
user_invocable: true
---

# /mascot-subagent-test - 子マスコットspawn/dismissテスト

Taskサブエージェント起動時のhook（`task_spawn_hook.py` / `task_dismiss_hook.py`）が
正しく子マスコットをspawn・dismissするかテストする。

## Usage

```
/mascot-subagent-test              # 2体並列テスト（デフォルト）
/mascot-subagent-test 3            # 3体並列テスト（最大）
/mascot-subagent-test --stop       # 全タスクマスコットを停止・クリーンアップ
```

## 停止 (`--stop`)

```bash
for pidfile in ~/.claude/utsutsu-code/task-*/mascot.pid; do
  if [ -f "$pidfile" ]; then
    pid=$(cat "$pidfile")
    kill "$pid" 2>/dev/null && echo "Stopped mascot PID $pid"
  fi
done
rm -rf ~/.claude/utsutsu-code/task-*/
echo "All task mascots stopped and cleaned up"
```

## 実行手順

### Step 1: メインマスコットの確認

```bash
pgrep -f "utsutsu_code" && echo "ALREADY_RUNNING" || echo "NOT_RUNNING"
```

`NOT_RUNNING` の場合 → 「先に `/mascot-run` でメインマスコットを起動してください」と案内して終了。

### Step 2: 既存タスクマスコットの確認

```bash
ls ~/.claude/utsutsu-code/task-*/mascot.pid 2>/dev/null && echo "EXISTING_TASKS" || echo "NO_TASKS"
```

`EXISTING_TASKS` の場合 → 停止するか確認。停止する場合は `--stop` の手順を実行。

### Step 3: サブエージェントTaskを並列起動

引数の数値分（デフォルト2、最大3）のTaskサブエージェントを**同時に**起動する。
各Taskは数秒sleepしてから終了する。hook が spawn/dismiss シグナルを発行する。

シグナルファイルは `spawn_child_{task_id}` 形式で個別に書かれるため、**並列起動で競合しない**。

```
Task tool (subagent_type: Bash)
prompt: "Run: sleep 8 && echo 'Task 0 done'"

Task tool (subagent_type: Bash)
prompt: "Run: sleep 8 && echo 'Task 1 done'"
```

2つのTaskを同時に起動する。3体テストの場合は3つ同時に起動。

### Step 4: テスト結果の確認

各Taskの起動・完了時に以下を確認:

1. **spawn確認**: Task起動時に画面に子マスコットが表示されたか
2. **dismiss確認**: Task完了時に子マスコットが消えたか
3. **マッピングの掃除**: dismiss後にマッピングファイルが削除されているか

```bash
ls ~/.claude/utsutsu-code/_task_mappings/ 2>/dev/null
```

空なら全タスクのdismissが正常に完了している。

### Step 5: 結果報告

テスト結果をユーザーに報告する:

- spawn: OK / NG（子マスコットが表示されたか）
- dismiss: OK / NG（子マスコットが消えたか）
- マッピング: OK / NG（ファイルが掃除されたか）

## 関連スキル

- `/mascot-run` — メインマスコット起動
- `/mascot-test` — 口パク・感情のテスト
- `/tsukuyomi-cleanup` — 全プロセス停止・リソース削除
