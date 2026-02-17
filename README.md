# utsutsu-code (うつつこーど)

Claude Code向けのデスクトップマスコットアプリです。
<img width="796" height="484" alt="tsukuyomi_typo" src="https://github.com/user-attachments/assets/7fb64c12-c1c8-49d8-8748-5a029a2fa91b" />

Claude CodeのSKILLベースで実行しています。
デフォルトではつくよみちゃんが起動します。macOS / Windows / Linux に対応しています。

## クイックスタート

### 前提条件

- [COEIROINKv2](https://coeiroink.com/download)
- macOS または Windows
- Python3
- Flutter SDK (3.10+) — macOS のみ。Windows はビルド済み exe を使用

### セットアップ

Claude Codeで `/tsukuyomi-setup` を実行すると、前提条件チェックからTTSテストまですべて対話的にセットアップできます。

```
/tsukuyomi-setup
```

#### Windows — 手動で行う場合:

1. [Python3](https://apps.microsoft.com/detail/9pnrbtzxmb4z) をインストール（Microsoft Store）
2. [COEIROINKv2](https://coeiroink.com/download) をインストールして起動
3. [Releases](https://github.com/sawarae/utsutsu-code/releases) から `utsutsu-code-windows.zip` をダウンロード
4. 任意の場所に展開
5. `mascot.exe` を起動

その後、`.claude` ディレクトリの内容を開発用のプロジェクト内にコピーしてください。

#### macOS — 手動で行う場合:

```bash
cd mascot
flutter pub get
make setup
flutter run -d macos
```

#### Linux — 手動で行う場合:

```bash
# Install dependencies
sudo apt-get install clang cmake ninja-build pkg-config libgtk-3-dev liblz4-tool
sudo apt-get install alsa-utils  # For audio playback

# Build and run
cd mascot
flutter pub get
flutter build linux
./build/linux/x64/release/bundle/mascot
```

**Platform-specific behavior on Linux:**

- ✅ Wander mode (≤5 children): Fully supported
- ✅ Swarm mode (>5 children): Fully supported
- ⚠️ Click-through optimization: Not supported (transparent areas remain interactive)
- ✅ Audio playback: Uses `aplay` (requires alsa-utils)
- ⚠️ Always-on-top: Depends on window manager support

## つくよみちゃんについて

このアプリでは、フリー素材キャラクター「[つくよみちゃん](https://tyc.rei-yumesaki.net/)」（© Rei Yumesaki）を使用しています。

### 立ち絵

- **素材名:** つくよみちゃん万能立ち絵素材
- **素材制作者:** 花兎\*
- **素材配布URL:** <https://tyc.rei-yumesaki.net/material/illust/>
- **利用規約:** <https://tyc.rei-yumesaki.net/about/terms/>

### ミニキャラ

- **素材名:** つくよみちゃん万能ミニキャラ素材
- **素材制作者:** きばやし
- **素材配布URL:** <https://tyc.rei-yumesaki.net/material/illust/>
- **利用規約:** <https://tyc.rei-yumesaki.net/about/terms/>
