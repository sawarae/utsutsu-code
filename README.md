# utsutsu-code (うつつこーど)

Claude Code向けAIコーディングアシスタント向けのデスクトップマスコットアプリです。
<img width="790" height="481" alt="tsukuyomi" src="https://github.com/user-attachments/assets/fea2be1c-d3c2-4c3c-9a7c-f0ae8360da08" />

Claude CodeのSKILLベースで実行しています。
デフォルトではつくよみちゃんが起動します。apple silicon Macのみ対応です。

## クイックスタート

### 前提条件
- [COEIROINKv2](https://coeiroink.com/download)
- Flutter SDK (3.10+)
- macOS
- Python3

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
make setup          # モデル + フォールバック画像のダウンロード
flutter run -d macos
```

その後、.claudeディレクトリの内容を開発用のプロジェクト内にコピーしてください。

## つくよみちゃんについて

このアプリでは、フリー素材キャラクター「[つくよみちゃん](https://tyc.rei-yumesaki.net/)」（© Rei Yumesaki）を使用しています。

- **素材名:** つくよみちゃん万能立ち絵素材
- **素材制作者:** 花兎\*
- **素材配布URL:** <https://tyc.rei-yumesaki.net/material/illust/>
- **利用規約:** <https://tyc.rei-yumesaki.net/about/terms/>
