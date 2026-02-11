# /mascot-multi - マルチマスコットインスタンス管理

タスクごとに専用のマスコットインスタンスを起動し、各タスクの通知を対応するマスコットにルーティングする。
タスクマスコットはミニモデル（1.5MB）・小さいウィンドウ・Dock非表示で起動される。

## Usage

```
/mascot-multi 2          # マスコット2体を起動
/mascot-multi 3          # マスコット3体を起動（最大）
/mascot-multi --stop     # 全タスクマスコットを停止・クリーンアップ
```

## 停止 (`--stop`)

```bash
# PIDファイルからタスクマスコットを停止
for pidfile in ~/.claude/utsutsu-code/task-*/mascot.pid; do
  if [ -f "$pidfile" ]; then
    pid=$(cat "$pidfile")
    kill "$pid" 2>/dev/null && echo "Stopped mascot PID $pid"
  fi
done

# シグナルDir・PIDファイルを削除
rm -rf ~/.claude/utsutsu-code/task-*/
echo "All task mascots stopped and cleaned up"
```

## 起動フロー

### Step 1: 引数からインスタンス数を取得

N = 引数の数値（デフォルト: 2、最大: 3）

ミニマスコットのウィンドウ: 264x400px（メイン: 424x528px）
配置間隔: 280px/体（264px + 16px間隔）

### Step 2: メインマスコットの確認

```bash
pgrep -f "utsutsu_code" && echo "MAIN_RUNNING" || echo "MAIN_NOT_RUNNING"
```

メインマスコットが起動していない場合は「先に `/mascot-run` でメインマスコットを起動してください」と案内。

### Step 3: 既存タスクマスコットの確認

```bash
ls ~/.claude/utsutsu-code/task-*/mascot.pid 2>/dev/null && echo "EXISTING_TASKS" || echo "NO_TASKS"
```

既存タスクマスコットがある場合は停止するか確認。

### Step 4: シグナルDir作成・マスコット起動

各タスクについて以下を実行:

```bash
# シグナルDir作成
mkdir -p ~/.claude/utsutsu-code/task-{i}/

# マスコット起動（バックグラウンド）
# --no-dock: macOS Dockに表示しない
# --width/--height: ミニサイズウィンドウ
# --model blend_shape_mini: ミニモデル（軽量1.5MB）
# offset-x: 424 + 280 * i でメインマスコットの右に配置
cd /path/to/mascot && flutter run -d macos \
  -a --signal-dir -a ~/.claude/utsutsu-code/task-{i}/ \
  -a --offset-x -a {424 + 280 * i} \
  -a --model -a blend_shape_mini \
  -a --width -a 264 -a --height -a 400 \
  -a --no-dock &

# PID記録
echo $! > ~/.claude/utsutsu-code/task-{i}/mascot.pid
```

**位置の計算:**
| インスタンス | offset-x | サイズ | 役割 |
|-------------|----------|--------|------|
| メイン | 0 | 424x528 | 親エージェント通知 |
| task-0 | 424 | 264x400 | サブエージェント#0 |
| task-1 | 704 | 264x400 | サブエージェント#1 |
| task-2 | 984 | 264x400 | サブエージェント#2 |

**重要**: `flutter run` はBashツールの `run_in_background: true` で起動すること。

### Step 5: 起動確認・テンプレート出力

各マスコットが起動したら、以下のテンプレートを出力:

```
マスコット {N} 体を起動しました:

Task 0:
  signal-dir: ~/.claude/utsutsu-code/task-0/
  TTS: python3 ~/.claude/hooks/mascot_tts.py --signal-dir ~/.claude/utsutsu-code/task-0/ --emotion KEY "msg"

Task 1:
  signal-dir: ~/.claude/utsutsu-code/task-1/
  TTS: python3 ~/.claude/hooks/mascot_tts.py --signal-dir ~/.claude/utsutsu-code/task-1/ --emotion KEY "msg"
```

## サブエージェント連携

親エージェントがTask subagentを起動するとき、promptに以下を含める:

```
このタスク専用のTTSコマンド（CLAUDE.mdのデフォルトの代わりに使用）:
python3 ~/.claude/hooks/mascot_tts.py --signal-dir ~/.claude/utsutsu-code/task-{i}/ --emotion KEY "要約(30文字以内)"
```

これにより、サブエージェントのTTS通知が対応するマスコットにルーティングされる。

## プラットフォーム別起動

**macOS デバッグ:**
```bash
cd /path/to/mascot && flutter run -d macos \
  -a --signal-dir -a ~/.claude/utsutsu-code/task-{i}/ \
  -a --offset-x -a {offset} \
  -a --model -a blend_shape_mini \
  -a --width -a 264 -a --height -a 400 \
  -a --no-dock
```

**macOS リリース:**
```bash
open -n /path/to/utsutsu_code.app --args \
  --signal-dir ~/.claude/utsutsu-code/task-{i}/ \
  --offset-x {offset} \
  --model blend_shape_mini \
  --width 264 --height 400 \
  --no-dock
```

## サブエージェント終了時のディスミス

サブエージェント完了後、対応するマスコットをポップエフェクト付きで消す:

```bash
python3 ~/.claude/hooks/mascot_tts.py --signal-dir ~/.claude/utsutsu-code/task-{i}/ --dismiss
```

これにより `mascot_dismiss` シグナルファイルが書かれ、マスコットが拡大→縮小+フェードアウト（0.3秒）で消える。

## クリーンアップ

タスク完了後、必ず `/mascot-multi --stop` で停止すること。
`/tsukuyomi-cleanup` でも全タスクマスコットが停止される。
