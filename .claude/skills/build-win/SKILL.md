---
name: build-win
description: Windows配布用zipビルド (exe + モデル + emotions)
user_invocable: true
---

# /build-win - Windows リリースビルド

Flutter Windows ビルドを実行し、モデルファイルを同梱した配布用 zip を作成する。

## 実行手順

### Step 1: 前提条件チェック

```bash
flutter --version 2>/dev/null && echo "OK" || echo "Flutter not found"
ls mascot/assets/models/blend_shape/*.inp 2>/dev/null && echo "Model OK" || echo "Model not found"
ls mascot/assets/models/blend_shape/emotions.toml 2>/dev/null && echo "Config OK" || echo "Config not found"
```

- Flutter が無い場合: 中断
- `.inp` が無い場合: 「モデルファイルが見つかりません。`/tsukuyomi-setup` を実行するか、手動で配置してください」と案内して中断

### Step 2: Flutter ビルド

```bash
cd mascot && flutter build windows
```

ビルド失敗時は Trouble 感情で TTS 通知してエラーを報告。

### Step 3: モデルファイル配置

Release ディレクトリにモデルを配置し、不要ファイルを除去:

```bash
cd mascot
mkdir -p build/windows/x64/runner/Release/data/models/blend_shape
mkdir -p build/windows/x64/runner/Release/data/config
cp assets/models/blend_shape/emotions.toml build/windows/x64/runner/Release/data/models/blend_shape/
cp assets/models/blend_shape/*.inp build/windows/x64/runner/Release/data/models/blend_shape/
cp config/emotions.toml build/windows/x64/runner/Release/data/config/
rm -f build/windows/x64/runner/Release/native_assets.json
```

### Step 4: zip 作成

PowerShell で圧縮（Windows 環境を想定）:

```bash
cd mascot && powershell -c "Compress-Archive -Path 'build\\windows\\x64\\runner\\Release\\*' -DestinationPath 'build\\utsutsu-code-windows.zip' -Force"
```

### Step 5: 完了報告

zip のサイズを確認して報告:

```bash
ls -lh mascot/build/utsutsu-code-windows.zip
```

TTS で完了通知:
```bash
python3 ~/.claude/hooks/mascot_tts.py --emotion Joy "ウィンドウズビルド完了しました"
```

## 出力

`mascot/build/utsutsu-code-windows.zip` に以下を含む（`build/` は .gitignore 済み）:

```
mascot.exe
flutter_windows.dll
screen_retriever_plugin.dll
window_manager_plugin.dll
data/
  app.so
  icudtl.dat
  flutter_assets/...
  config/
    emotions.toml
  models/blend_shape/
    emotions.toml
    *.inp
```

ユーザーは zip を展開して `mascot.exe` をそのまま実行できる。
