# utsutsu-code iOS Remote

iOSからClaude Codeのターミナルセッションをリアルタイム監視し、つくよみちゃんにお願いできるアプリ。

## アーキテクチャ

```
┌──────────────┐     WebSocket     ┌──────────────┐     Signal File     ┌──────────────┐
│   iOS App    │ ◄──────────────► │ Relay Server │ ──────────────────► │   Desktop    │
│ (SwiftUI)    │                   │  (Python)    │                     │   Mascot     │
└──────────────┘                   └──────────────┘                     └──────────────┘
                                         ▲
                                         │ session.jsonl
                                   ┌─────┴──────┐
                                   │ Claude Code │
                                   │  (Hooks)    │
                                   └─────────────┘
```

## コンポーネント

### 1. Relay Server (`server/`)
- Python WebSocketサーバー
- `session.jsonl` を監視してiOSにストリーミング
- iOSからのTTSリクエストをシグナルファイルに中継
- Bonjour/mDNSで自動検出（オプション）

### 2. Session Logger (`server/session_logger.py`)
- Claude Codeフック経由でセッション活動をJSONLに記録
- ツール呼び出し、アシスタント応答、エラー等を構造化ログ

### 3. iOS App (`UtsutsuRemote/`)
- **セッションビュー**: ターミナルライクなリアルタイムログ表示
- **お願いビュー**: つくよみちゃんへのTTSリクエスト（感情選択付き）
- **接続ビュー**: Bonjourサーバー自動検出 / 手動接続
- ローカル通知でタスク完了・エラーを通知

## セットアップ

### PC側（リレーサーバー）

```bash
cd ios-remote
./setup.sh
```

または手動で:

```bash
cd ios-remote/server
pip install -r requirements.txt
python3 relay_server.py
```

環境変数:
- `RELAY_PORT` - WebSocketポート（デフォルト: 8765）
- `RELAY_HOST` - バインドアドレス（デフォルト: 0.0.0.0）

### iOS側

1. Xcodeで `UtsutsuRemote/` を開く
   - XcodeGenの場合: `xcodegen generate` → `.xcodeproj` を開く
   - SPMの場合: `Package.swift` をXcodeで開く
2. iPhoneにビルド＆インストール
3. アプリの「接続」タブでサーバーを選択

### Claude Codeフック設定

`.claude/settings.json` に以下を追加:

```json
{
  "hooks": {
    "PostToolUse": [
      {
        "matcher": "",
        "hooks": [
          {
            "type": "command",
            "command": "bash /path/to/utsutsu-code/.claude/hooks/session_log.sh"
          }
        ]
      }
    ]
  }
}
```

## プロトコル

### Server → Client

| type | data | 説明 |
|------|------|------|
| `session_line` | `{timestamp, kind, content}` | セッションログ1行 |
| `session_lines` | `[{timestamp, kind, content}, ...]` | 履歴一括送信 |
| `notify` | `{title, body, emotion}` | 通知イベント |
| `status` | `{connected, session_active}` | 接続状態 |

### Client → Server

| type | data | 説明 |
|------|------|------|
| `tts` | `{message, emotion}` | TTSリクエスト |
| `ping` | - | 生存確認 |

### Session Line Kinds

| kind | 説明 |
|------|------|
| `assistant` | Claudeの応答テキスト |
| `tool_call` | ツール呼び出し |
| `tool_output` | ツール出力 |
| `task_complete` | タスク完了 |
| `error` | エラー発生 |
| `test_result` | テスト結果 |
| `session_start` | セッション開始 |
| `session_end` | セッション終了 |
| `tts_request` | iOS→TTS |
