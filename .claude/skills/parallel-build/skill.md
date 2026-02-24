---
name: parallel-build
description: インターフェース定義→並列実装→統合テストの3フェーズでプロジェクトを構築
---

# Parallel Build Skill

複数のsubagentでプロジェクトを並列構築するスキル。
インターフェース契約を先に定義してからsubagentに渡すことで、並列開発時のAPI不整合を防ぐ。

## なぜ必要か

5つのsubagentが並列でモジュールを書くと、以下が起きる:
- 関数シグネチャの不一致 (`use_color=` vs `no_color=`)
- データクラスのフィールド名不一致 (`text=` vs `message=`)
- エラーハンドリングの方針不一致 (`raise` vs `return None`)

**解決策**: Phase 1 で共有インターフェースを定義し、全agentに渡す。

## 引数

```bash
/parallel-build <spec-file-or-description>

# 例:
/parallel-build demo/README.md          # READMEの仕様から構築
/parallel-build "Python占いCLI、5モジュール"  # テキスト記述
/parallel-build                          # インタラクティブ
```

## 実行フロー

```
Phase 1: インターフェース定義（直列・1 agent）
  └─ スタブファイル生成（型・シグネチャ・docstring のみ）
      ↓
Phase 2: 並列実装（N agents 同時）
  ├─ Agent 1: モジュールA実装（スタブ参照）
  ├─ Agent 2: モジュールB実装（スタブ参照）
  ├─ Agent 3: モジュールC実装（スタブ参照）
  ├─ Agent 4: モジュールD実装（スタブ参照）
  └─ Agent 5: テスト実装（スタブ参照）
      ↓
Phase 3: 統合テスト＋修正（直列・1 agent）
  └─ テスト実行 → 失敗箇所を修正 → 全パスまで繰り返し
```

### Phase 1: インターフェース定義

**目的**: 全モジュール間の契約を先に決める

1. ユーザーの仕様（spec file / 引数テキスト）を読む
2. Task tool で **1つの agent** を起動し、以下を生成させる:

```
Task(
  subagent_type: "general-purpose",
  description: "Generate interface stubs",
  prompt: """
以下の仕様に基づいて、全モジュールのインターフェーススタブを生成してください。

## 仕様
{spec_content}

## 出力要件
各モジュールについて、以下だけを含むスタブファイルを作成:
- クラス/dataclass定義（フィールド名・型のみ、実装なし）
- 関数シグネチャ（引数名・型・戻り値型のみ、bodyは `...` or `pass`）
- 定数定義
- docstring（動作仕様を明記、特にエラー時の挙動）

## 重要
- 実装コードは書かない（型とシグネチャだけ）
- エラーハンドリングの方針を docstring に明記（例: "見つからない場合は None を返す"）
- 引数名は全モジュールで統一する（例: no_color は no_color で統一、use_color にしない）
- 出力先: {output_dir}/_stubs/ に各モジュール名.pyi として保存
"""
)
```

**生成されるスタブ例**:

```python
# _stubs/core.pyi
from dataclasses import dataclass

@dataclass
class Fortune:
    """占い1件のデータ。"""
    message: str      # 占いメッセージ（"text" ではなく "message"）
    mood: str         # 感情キー（"Gentle", "Joy" 等）
    lucky_item: str
    lucky_color: str

def load_fortunes(path: str | Path | None = None) -> list[Fortune]:
    """JSONから占い一覧を読み込む。path省略時はデフォルトパス。"""
    ...

def get_random_fortune(fortunes: list[Fortune], mood: str | None = None) -> Fortune | None:
    """ランダムに1件選択。mood指定時はフィルタ。該当なしはNoneを返す（例外は投げない）。"""
    ...
```

### Phase 2: 並列実装

**目的**: スタブを参照しながら各agentが独立して実装

1. Phase 1 で生成されたスタブファイルをすべて読み込む
2. 仕様からタスク分割を決定（ユーザー指定 or 自動分割）
3. 全タスクを **同時に** Task tool で起動:

```
# 全タスクを1つのメッセージ内で同時に呼ぶ（重要）
for each task in tasks:
  Task(
    subagent_type: "general-purpose",
    description: f"Build {task.name}",
    prompt: f"""
{task.description}

## インターフェース契約（厳守）

以下のスタブに定義された型・シグネチャ・エラーハンドリング方針に従うこと。
シグネチャの変更は禁止。

```
{all_stubs_content}
```

## 出力先
{task.output_files}

## ルール
- スタブのシグネチャを変更しない
- 引数名をスタブと一致させる
- エラーハンドリングはdocstringの記述に従う
- 他モジュールの import はスタブのクラス名・関数名をそのまま使う
"""
  )
```

**各agentへの注入内容**:
- 自分の担当ファイルの説明
- **全モジュールのスタブ**（自分の担当外も含む — import先を知るため）
- インターフェース遵守ルール

### Phase 3: 統合テスト＋修正

**目的**: 並列実装の結果を統合し、不整合を修正

1. 全agentの完了を待つ
2. テストを実行:

```bash
# Python の場合
python3 -m unittest discover -s tests -v
# or
python3 -m pytest tests/ -v
```

3. **全パスなら完了** → 成果を報告
4. **失敗があれば修正**:

```
Task(
  subagent_type: "general-purpose",
  description: "Fix integration issues",
  prompt: f"""
以下のテスト失敗を修正してください。

## テスト結果
{test_output}

## インターフェース契約
{all_stubs_content}

## ルール
- スタブのシグネチャが正。実装がスタブと異なる場合は実装を修正する
- テスト側がスタブと異なる場合はテストを修正する
- 修正は最小限にする
"""
)
```

5. テスト再実行 → 全パスまでループ（最大3回）

## 完了時の出力

```markdown
## Parallel Build 完了

### Phase 1: インターフェース定義
- スタブファイル: N 個生成
- 定義: クラス X 個、関数 Y 個

### Phase 2: 並列実装
- Agent 1: {name} → {files} ✅
- Agent 2: {name} → {files} ✅
- Agent 3: {name} → {files} ✅
- Agent 4: {name} → {files} ✅
- Agent 5: {name} → {files} ✅

### Phase 3: 統合テスト
- テスト数: N 件
- 結果: 全パス ✅
- 修正回数: 0 回

### 生成ファイル
{file_tree}
```

## 仕様ファイルのフォーマット

仕様は自由形式だが、以下を含むと精度が上がる:

```markdown
## プロジェクト名
tsukuyomi-fortune

## 言語・ランタイム
Python 3.10+、外部依存なし

## ディレクトリ構成
(ファイルツリー)

## モジュール定義
### モジュール1: core
- 担当ファイル: core.py
- 概要: データモデル、CRUD
- 公開API:
  - Fortune dataclass (message, mood, lucky_item, lucky_color)
  - load_fortunes(path) -> list[Fortune]
  - get_random_fortune(fortunes, mood=None) -> Fortune | None

### モジュール2: display
- 担当ファイル: display.py
- 概要: ターミナル表示
- 公開API:
  - render_fortune(fortune, mood_info=None, no_color=False) -> str
  ...

## テスト
pytest, unittest.TestCase ベース
```

## エラー時の動作

| 状況 | 動作 |
|------|------|
| Phase 1 失敗 | エラー報告して終了 |
| Phase 2 の一部agent失敗 | 他agentの結果は保持。失敗分のみリトライ提案 |
| Phase 3 テスト失敗 | 修正agentを起動（最大3回リトライ） |
| 3回リトライしても失敗 | テスト結果を報告してユーザーに判断を委ねる |

## デモとの連携

マスコットアプリ起動中は、各Phase 2 の Task tool 呼び出しで子マスコットが自動spawn。
Phase 3 の修正agentでも子マスコットが出る。

```
Phase 1: 親マスコットのみ（1体）
Phase 2: 子マスコット N体 spawn（Task hook 経由）
Phase 3: 子マスコット 1体 spawn（修正agent）
```

---

**サイズ**: ~200行
**目的**: インターフェース定義先行の並列プロジェクト構築
**前提スキル**: なし（独立）
