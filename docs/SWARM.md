# スウォームオーバーレイ アーキテクチャ

子マスコットを1つのフルスクリーン透過ウィンドウで一括描画する仕組み。
従来のマルチプロセス方式（子1体ごとにFlutterプロセス）では5体で250%CPUだったが、
スウォーム方式では1000体でも約35%CPUで動作する。

## 概要

```
親マスコット (main.dart)
  │
  └─ スウォームオーバーレイ (単一プロセス・フルスクリーン透過ウィンドウ)
       ├─ SwarmSimulation   … 1つのTicker、全エンティティの物理演算
       ├─ SwarmPainter       … 1つのCustomPainter、全スプライト描画 (LOD1)
       ├─ BubblePainter      … 吹き出し描画（LOD0の上のレイヤー）
       ├─ SpriteCache        … パペットモデルの事前レンダリング (2x Retina)
       ├─ CollisionGrid      … 空間ハッシュによるO(n)衝突判定
       └─ SignalMonitor      … シグナルファイルの一括ポーリング
```

## LOD（Level of Detail）

| レベル | 対象 | 描画方法 | コスト |
|--------|------|----------|--------|
| LOD1 | 全エンティティ | `SwarmPainter` でスプライト画像をバッチ描画 | 低い（drawImageRect） |
| LOD0 | アクティブな1体 | `MascotWidget`（フルパペット）をオーバーレイ | 高い（リグ＋表情） |

### LOD0への昇格トリガー

- ドラッグ開始
- TTS（`mascot_speaking`）受信
- タップ

### LOD0からの降格

`lod0_timeout_ms`（デフォルト6秒）操作なしで自動降格。

### フラッシュ防止

LOD0のMascotWidgetは非同期でモデルをロードするため、読み込み中にスプライトが消えないよう
SwarmPainterは**LOD0エンティティのスプライトも常に描画**する。MascotWidgetが読み込まれたら上に重なる。

## ファイル構成

```
mascot/lib/swarm/
  mascot_entity.dart      … エンティティデータクラス（ChangeNotifierなし）
  swarm_simulation.dart   … 物理演算・Ticker（~30fps通知）
  swarm_painter.dart      … LOD1スプライト描画 + BubblePainter
  swarm_app.dart          … エントリウィジェット・LOD管理・ドラッグ・スポーン監視
  sprite_cache.dart       … 事前レンダリング済みスプライトキャッシュ
  collision_grid.dart     … 空間ハッシュグリッド
  signal_monitor.dart     … シグナルファイル一括ポーリング
```

## エンティティのライフサイクル

```
1. spawn_child シグナルファイルが書き込まれる
   │
2. SwarmApp が検出 → JSON解析 → task_id を取得
   │
3. addEntity() → 画面上部のランダムX位置に配置、isDropping=true
   │
4. 落下物理演算 → 着地 → バウンス → 通常徘徊
   │
5. 徘徊中: 移動・バウンス・方向転換・腕状態変更・キラキラ
   │
6. mascot_dismiss 検出 → エンティティ削除 → シグナルディレクトリ削除
```

## シグナルファイルプロトコル

すべてのシグナルは `~/.claude/utsutsu-code/` 配下に置かれる。

### spawn_child

親ディレクトリに書き込み。SwarmAppがリネーム（アトミック取得）して処理。

```json
{
  "version": 1,
  "payload": { "task_id": "abc12345" }
}
```

### mascot_speaking

各エンティティの `task-{id}/` ディレクトリに書き込み。

```json
{
  "version": 1,
  "payload": {
    "message": "タスク開始します",
    "emotion": "Gentle"
  }
}
```

レガシー形式（エンベロープなし）と平文テキストも後方互換でサポート。

**最小表示時間**: `minBubbleDurationMs`（5秒）。`mascot_tts.py`が音声再生後にファイルを削除しても、
5秒間は吹き出しを表示し続ける。ファイルが存在する間はメッセージの更新も反映される。

### mascot_dismiss

空ファイルの存在で検出。`SignalMonitor`が200msごとにチェック。

## 設定 (window.toml)

```toml
[swarm]
swarm_threshold = 0           # max_children > この値でスウォームモード
lod0_timeout_ms = 6000        # LOD0自動降格までの時間
signal_poll_ms = 200          # シグナルファイルのポーリング間隔
click_through_interval = 0.05 # クリックスルー判定間隔（秒）
bottom_margin = 50            # スプライト足元の透明パディング補正
```

`swarm_threshold = 0` → 常にスウォームモード（デフォルト）。
`swarm_threshold = 5` → 子マスコット5体以下は従来のwanderプロセス。

## パフォーマンス最適化

### 描画スロットリング

```dart
// ~30fpsに制限（60fpsフルだと不要な負荷）
if (nowMs - _lastNotifyMs < 33) return;
notifyListeners();
```

### 衝突判定スロットリング

```dart
// ~20Hz（3フレームに1回）
if (++_collisionSkipCounter >= 3) {
  _collisionSkipCounter = 0;
  _grid.resolveCollisions();
}
```

### 空間ハッシュ (CollisionGrid)

- セルサイズ = エンティティ幅
- `cellKey = cx * 100000 + cy` でO(1)ルックアップ
- リスト再利用（clear、再生成しない）→ GC圧力軽減
- ペア重複排除でN^2を回避

### スプライトキャッシュ

起動時に全バリエーション（感情 × 腕 × 向き × 口）を2x解像度でプリベイク。
描画時はO(1)のMap参照のみ。

### ベンチマーク結果（M1 Mac）

| エンティティ数 | CPU使用率 |
|---------------|----------|
| 0（空ウィンドウ） | ~8% |
| 50（衝突なし） | ~21% |
| 50（衝突あり） | ~35% |
| 1000 | ~35% |

## クリックスルー（macOS）

従来の方式（`CGWindowListCreateImage`でビットマップキャプチャ）は高コスト。
スウォームモードではエンティティの矩形リストをFlutter→Swiftに送り、
マウス位置との純粋な数学的判定のみで行う。

```swift
// Flutter側: 100msごとにエンティティ矩形を送信
_swarmModeChannel.invokeMethod('updateEntityRects', rects);

// Swift側: マウスがどの矩形にもなければクリックスルー
self.ignoresMouseEvents = !overEntity
```

## 描画レイヤー順序（SwarmApp Stack）

```
1. SwarmPainter    … LOD1スプライト（全エンティティ）
2. MascotWidget    … LOD0フルパペット（アクティブな1体）
3. BubblePainter   … 吹き出し（全エンティティ、LOD0の上）
```

吹き出しを最上位レイヤーにすることで、LOD0のMascotWidgetに隠されない。
