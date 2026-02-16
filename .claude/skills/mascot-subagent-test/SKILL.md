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

### Step 1: 簡易テスト（test_child.sh）

まず同梱の `test_child.sh` でスポーン→TTS→ディスミスの基本フローを確認する:

```bash
bash .claude/skills/mascot-subagent-test/test_child.sh
```

全パスなら Step 2 へ。失敗した場合はここで原因を調査する。

### Step 2: サブエージェントTTS統合テスト

test_child.sh は直接 Bash で TTS を送るが、このステップでは Task tool 経由でサブエージェントから TTS を送り、プロセス分離を検証する。

```bash
# --keep で子マスコットを残す
bash .claude/skills/mascot-subagent-test/test_child.sh --keep
```

出力の `SIGNAL_DIR` を控え、Task tool でサブエージェントを起動:

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

確認後、ディスミス:

```bash
touch SIGNAL_DIR/mascot_dismiss
sleep 3 && pgrep -f "utsutsu_code" | wc -l
rm -rf SIGNAL_DIR
```

### --parallel の場合

`test_child.sh --keep` を2回実行し、それぞれの SIGNAL_DIR に対して Task tool を並列で呼び出す:

```
Task #0: --signal-dir SIGNAL_DIR_0 --emotion Gentle "ゼロ号機です"
Task #1: --signal-dir SIGNAL_DIR_1 --emotion Gentle "壱号機です"
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
- 簡易テスト (test_child.sh): OK / NG
- サブエージェントTTS: OK / NG（エンジン: coeiroink / none）
- ディスミス: OK / NG
- プロセス数: 開始前 X → スポーン後 Y → ディスミス後 Z
```
