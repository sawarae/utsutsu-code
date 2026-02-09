# utsutsu-code (うつつこーど)

Claude Code向けのデスクトップマスコットアプリです。
<img width="796" height="484" alt="tsukuyomi_typo" src="https://github.com/user-attachments/assets/7fb64c12-c1c8-49d8-8748-5a029a2fa91b" />

Claude CodeのSKILLベースで実行しています。
デフォルトではつくよみちゃんが起動します。macOS / Windows に対応しています。

## クイックスタート

### 前提条件
- [COEIROINKv2](https://coeiroink.com/download)
- macOS または Windows
- Python3
- Flutter SDK (3.10+) (mac)

### セットアップ

Claude Codeで `/tsukuyomi-setup` を実行すると、前提条件チェックからTTSテストまですべて対話的にセットアップできます。

```
/tsukuyomi-setup
```

マスコットのみ起動する場合は

```
/mascot-run
```
です。

#### 手動で行う場合:

```bash
cd mascot
flutter pub get
make setup          # モデル + フォールバック画像のダウンロード (gh CLI が必要)
flutter run -d macos    # macOS
```

`make` や `gh` CLI がない環境では、以下から手動でダウンロードしてください:

#### windows
1. **モデルファイル**: [utsutsu2d v0.01](https://github.com/sawarae/utsutsu2d/releases/tag/v0.01) から `tsukuyomi_blend_shape.inp` をダウンロード → `mascot/assets/models/blend_shape/` に配置

#### ビルド済み exe を使う場合:

```bash

# exe と同階層の data/models/ にモデルを配置
# build/windows/x64/runner/Release/
#   ├── mascot.exe
#   └── data/models/blend_shape/
#       ├── tsukuyomi_blend_shape.inp
#       └── emotions.toml
```


その後、.claudeディレクトリの内容を開発用のプロジェクト内にコピーしてください。

## つくよみちゃんについて

このアプリでは、フリー素材キャラクター「[つくよみちゃん](https://tyc.rei-yumesaki.net/)」（© Rei Yumesaki）を使用しています。

- **素材名:** つくよみちゃん万能立ち絵素材
- **素材制作者:** 花兎\*
- **素材配布URL:** <https://tyc.rei-yumesaki.net/material/illust/>
- **利用規約:** <https://tyc.rei-yumesaki.net/about/terms/>
