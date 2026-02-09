# utsutsu-code (うつつこーど)

Claude Code向けAIコーディングアシスタント向けのデスクトップマスコットアプリです。

<a href="https://gyazo.com/3fb61b097667b789bdb3aa017069ba9c"><img src="https://i.gyazo.com/3fb61b097667b789bdb3aa017069ba9c.gif" alt="Image from Gyazo" width="600"/></a>

Claude CodeのSKILLベースで実行しています。
apple silicon Macのみ対応です。

## クイックスタート

### 前提条件

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
