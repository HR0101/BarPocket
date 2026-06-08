# BarPocket

macOS 向けの「一時ファイル置き場」ユーティリティです．メニューバーのアイコン，または通常ウインドウにファイルをドラッグ＆ドロップして一時的にストックし，必要なときに Finder や他アプリへ取り出せます．

## 概要

ファイルを「いったん置いておく」ための小さな常駐アプリです．ストックしたファイルはアプリ専用フォルダにコピーして保持されるため，元ファイルを移動・削除しても安全です．取り出し方法によって「移動（消える）」と「複製（残す）」を使い分けられます．

## 主な機能

- **2 つの入口**: メニューバーアイコンへの D&D と，Dock に出る通常ウインドウへの D&D の両対応．
- **複数選択**: クリック／⌘クリック（個別追加）／⇧クリック（範囲選択）で複数のファイルを選択できます．
- **ドラッグで取り出し（消える）**: 選択した項目を Finder 等へドラッグすると，コピー完了後にリストから自動的に消えます．
- **コピーで複製（残す）**: ⌘C または各行のコピーボタンでクリップボードへコピーすると，リストには残ります．
- **ログイン時に自動起動 / 常駐**: 設定トグルで自動起動を切り替え，ウインドウを閉じても常駐します．

## 動作環境

- macOS 13 以降（自動起動に `SMAppService` を使用）
- Xcode 16 以降（`objectVersion = 77` のファイルシステム同期グループを使用）
- Swift 5

## ビルドと実行

### Xcode で実行

1. `BarPocket.xcodeproj` を Xcode で開きます．
2. スキーム `BarPocket` を選び，実行（⌘R）します．

### スタンドアロンアプリとして配置

Xcode を閉じても常駐させたい場合は，Release ビルドを `/Applications` へ配置します．プロジェクト直下で次を実行します．

```bash
xcodebuild -project BarPocket.xcodeproj -scheme BarPocket \
  -configuration Release -derivedDataPath build/Rel build
pkill -x BarPocket 2>/dev/null
rm -rf /Applications/BarPocket.app
cp -R build/Rel/Build/Products/Release/BarPocket.app /Applications/
open -a /Applications/BarPocket.app
```

## 使い方

1. ファイルをメニューバーのアイコン，またはウインドウへドラッグ＆ドロップして追加します．
2. メニューバーアイコンをクリックするとポップオーバーで一覧が開きます（ウインドウでも同じ一覧を表示）．
3. 行をクリックして選択し，Finder へドラッグすると取り出せます（リストからは消えます）．
4. ⌘C／コピーボタンでコピーした場合は，リストに残ります．
5. 個別削除（×）・全クリア（🗑）・全選択（☑）も利用できます．

## プロジェクト構成

| ファイル | 役割 |
| --- | --- |
| `BarPocketApp.swift` | エントリポイント．`WindowGroup`（GUI）と `AppDelegate`（常駐制御）を構成 |
| `StatusItemController.swift` | メニューバーの `NSStatusItem` とポップオーバー，アイコンへの D&D 受け入れ |
| `FileStore.swift` | 保持ファイルの管理（追加・取り出し・コピー・選択・起動時復元） |
| `FileDragView.swift` | ポップオーバー/ウインドウからの取り出しドラッグ（`NSFilePromiseProvider`） |
| `PopoverView.swift` | SwiftUI 製の共通 UI（`StashContentView` / `MainView` / `PopoverView`） |
| `LoginItemManager.swift` | ログイン時自動起動（`SMAppService`）の管理 |

## 技術的なポイント

- **ファイル保持**: ドロップされたファイルは `Application Support/BarPocket/Stash/` へコピーして保持し，起動時に復元します．
- **取り出し**: `NSFilePromiseProvider` を用い，ドロップ先のコピー完了後に元を削除します（コピー処理とのレースによるエラー -43 を防止）．
- **両対応**: `LSUIElement = NO` ＋ `NSApp.setActivationPolicy(.regular)` で Dock 表示とメニューバー常駐を両立しています．

## Info.plist（ビルド設定）の要点

本プロジェクトは `GENERATE_INFOPLIST_FILE = YES`（物理 Info.plist なし）のため，ビルド設定キーで指定しています．

- `INFOPLIST_KEY_LSUIElement = NO` … Dock に表示する通常アプリにします．
- App Sandbox（`ENABLE_APP_SANDBOX = YES`）有効．D&D はユーザー操作のため追加 entitlement なしで動作します．

## 注意事項

- **自動起動の承認**: 開発署名の場合，初回オン時にシステムの承認が必要なことがあります．「システム設定 ▸ 一般 ▸ ログイン項目」で BarPocket を許可してください．
- **配置場所**: 自動起動はアプリのパスに紐づくため，`/Applications` に固定して使うのが安全です．
- **アセット**: `Assets.xcassets` は `.gitignore` で除外しています．クローン後は必要に応じてアプリアイコン等を再作成してください．
