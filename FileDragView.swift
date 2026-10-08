//
//  FileDragView.swift
//  BarPocket
//
//  ポップオーバー内のファイル項目を Finder や他アプリへドラッグ＆ドロップで
//  取り出すための AppKit ベースのドラッグ元ビュー.
//  クリックによる選択(⌘・⇧での複数選択)と, 選択した複数項目の一括ドラッグ,
//  取り出し完了の検知によるリストからの自動クリアを担当する.
//
//  ファイルの受け渡しには NSFilePromiseProvider(ファイルプロミス)を用いる.
//  ドロップ先がファイルを要求してきた時点で実体をコピーし, コピー完了後に
//  元の項目を削除するため, Finder のコピー処理とのレース(エラー -43)を防ぐ.
//

import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// ファイルをドラッグして取り出せる透明オーバーレイ.
struct FileDragView: NSViewRepresentable {
  /// この行が表す項目.
  let item: StashItem
  /// 選択状態とドラッグ対象を解決するためのストア.
  let store: FileStore

  func makeNSView(context: Context) -> DraggingSourceView {
    let view = DraggingSourceView()
    view.item = item
    view.store = store
    return view
  }

  func updateNSView(_ nsView: DraggingSourceView, context: Context) {
    nsView.item = item
    nsView.store = store
  }
}

/// ドラッグ元として振る舞い, クリック選択も処理する NSView.
final class DraggingSourceView: NSView, NSDraggingSource, NSFilePromiseProviderDelegate {
  var item: StashItem?
  weak var store: FileStore?

  /// マウスダウン位置(ドラッグ開始判定用).
  private var mouseDownPoint: NSPoint = .zero
  /// ドラッグ開始とみなす最小移動距離(ポイント).
  private let dragThreshold: CGFloat = 4
  /// このマウス操作でドラッグが発生したか.
  private var didDrag = false
  /// 修飾キーなしのクリックだったか.
  private var clickedWithoutModifier = false
  /// マウスダウン時点で既に選択済みの項目だったか.
  private var wasAlreadySelected = false

  // ポップオーバーが非アクティブでも最初のクリックからドラッグできるようにする.
  override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
    true
  }

  override func mouseDown(with event: NSEvent) {
    mouseDownPoint = event.locationInWindow
    didDrag = false
    clickedWithoutModifier = false

    guard let item, let store else { return }

    // UX改善: ダブルクリックでファイルを直接開く.
    if event.clickCount == 2 {
      NSWorkspace.shared.open(item.url)
      return
    }

    let flags = event.modifierFlags

    if flags.contains(.command) {
      // ⌘クリック: 選択状態をトグルする.
      store.toggleSelection(item)
    } else if flags.contains(.shift) {
      // ⇧クリック: 起点から範囲選択する.
      store.extendSelection(to: item)
    } else {
      // 修飾なし: すでに選択済みなら維持(ドラッグに備える), 未選択なら単独選択.
      clickedWithoutModifier = true
      wasAlreadySelected = store.isSelected(item)
      if !wasAlreadySelected {
        store.selectSingle(item)
      }
    }
  }

  override func mouseDragged(with event: NSEvent) {
    guard let item, let store else { return }

    // しきい値を超えて動いたらドラッグセッションを開始する.
    let current = event.locationInWindow
    let distance = hypot(
      current.x - mouseDownPoint.x,
      current.y - mouseDownPoint.y
    )
    guard distance > dragThreshold else { return }
    didDrag = true

    // 起点項目が選択中なら選択集合全体, そうでなければ単体をドラッグする.
    let targets = store.dragItems(activatedBy: item)
    guard !targets.isEmpty else { return }

    // 対象項目ごとにファイルプロミスを生成し, アイコンを少しずつずらして重ねる.
    let iconSize = NSSize(width: 32, height: 32)
    let localPoint = convert(event.locationInWindow, from: nil)
    var draggingItems: [NSDraggingItem] = []

    for (index, target) in targets.enumerated() {
      // 拡張子などから書き出すファイルの種別を決める.
      let provider = NSFilePromiseProvider(
        fileType: fileType(for: target),
        delegate: self
      )
      // 書き出し時にどの項目かを判別できるよう保持しておく.
      provider.userInfo = target

      let draggingItem = NSDraggingItem(pasteboardWriter: provider)
      let icon = NSWorkspace.shared.icon(forFile: target.url.path)
      let offset = CGFloat(index) * 6
      let dragFrame = NSRect(
        x: localPoint.x - iconSize.width / 2 + offset,
        y: localPoint.y - iconSize.height / 2 - offset,
        width: iconSize.width,
        height: iconSize.height
      )
      draggingItem.setDraggingFrame(dragFrame, contents: icon)
      draggingItems.append(draggingItem)
    }

    beginDraggingSession(with: draggingItems, event: event, source: self)
  }

  override func mouseUp(with event: NSEvent) {
    guard let item, let store else { return }
    // 修飾なしクリックで, ドラッグせず, 既存の選択内の項目をクリックした場合は
    // 単独選択へ絞り込む(macOS 標準の挙動に合わせる).
    if clickedWithoutModifier && !didDrag && wasAlreadySelected {
      store.selectSingle(item)
    }
  }

  /// 項目に対応する UTType 識別子を返す.
  private func fileType(for item: StashItem) -> String {
    let values = try? item.url.resourceValues(forKeys: [.isDirectoryKey])
    if values?.isDirectory == true {
      return UTType.folder.identifier
    }
    if let type = UTType(filenameExtension: item.url.pathExtension) {
      return type.identifier
    }
    return UTType.data.identifier
  }

  // MARK: - NSDraggingSource

  func draggingSession(
    _ session: NSDraggingSession,
    sourceOperationMaskFor context: NSDraggingContext
  ) -> NSDragOperation {
    // 取り出しはコピーで提供し, 元の削除はプロミス書き出し完了後にアプリが行う.
    .copy
  }

  // MARK: - NSFilePromiseProviderDelegate

  /// 書き出すファイル名を返す.
  func filePromiseProvider(
    _ filePromiseProvider: NSFilePromiseProvider,
    fileNameForType fileType: String
  ) -> String {
    (filePromiseProvider.userInfo as? StashItem)?.name ?? "BarPocketFile"
  }

  /// ドロップ先が要求してきたタイミングで実体をコピーし, 完了後に元を削除する.
  func filePromiseProvider(
    _ filePromiseProvider: NSFilePromiseProvider,
    writePromiseTo destination: URL,
    completionHandler: @escaping (Error?) -> Void
  ) {
    guard let item = filePromiseProvider.userInfo as? StashItem else {
      completionHandler(CocoaError(.fileNoSuchFile))
      return
    }

    do {
      // ドロップ先(システムが用意した書き込み可能 URL)へコピーする.
      try FileManager.default.copyItem(at: item.url, to: destination)
      completionHandler(nil)
      // コピーが完了してから, 元の項目をリストと実体から取り除く(取り出し＝消える).
      // 取り出し完了時は実体を完全に削除し、ゴミ箱の肥大化を防ぐ.
      // 保守性向上のため、UI・状態の更新は必ずメインスレッドで行う.
      DispatchQueue.main.async {
        self.store?.removeItems([item], permanently: true)
      }
    } catch {
      // コピーに失敗した場合は元を残し、中途半端なコピー先ファイルがあれば削除してロールバック（元に戻す）する.
      try? FileManager.default.removeItem(at: destination)
      NSLog("BarPocket: 取り出しコピーに失敗しました - \(error.localizedDescription)")
      completionHandler(error)
    }
  }
}
