//
//  StatusItemController.swift
//  BarPocket
//
//  メニューバーのアイコン(NSStatusItem)とポップオーバー(NSPopover)を管理する.
//  アイコンへのドラッグ＆ドロップ受け入れもここで処理する.
//

import AppKit
import SwiftUI

/// メニューバーアイコンとポップオーバーを統括するコントローラ.
final class StatusItemController: NSObject {
  private let statusItem: NSStatusItem
  private let popover = NSPopover()
  private let store: FileStore
  private let loginManager: LoginItemManager

  init(store: FileStore, loginManager: LoginItemManager) {
    self.store = store
    self.loginManager = loginManager
    // 可変長のステータスアイテムをメニューバーへ追加する.
    statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    super.init()

    configureButton()
    configurePopover()
  }

  // MARK: - セットアップ

  /// メニューバーボタンの見た目とドロップ受け入れビューを構成する.
  private func configureButton() {
    guard let button = statusItem.button else { return }

    // テンプレート画像を使い, ライト/ダーク両モードで自然に表示させる.
    let image = NSImage(
      systemSymbolName: "archivebox",
      accessibilityDescription: "BarPocket"
    )
    image?.isTemplate = true
    button.image = image

    // ドラッグ＆ドロップとクリックを処理するビューをボタン全面へ重ねる.
    let dropView = StatusDropView(frame: button.bounds)
    dropView.autoresizingMask = [.width, .height]
    dropView.onClick = { [weak self] in
      self?.togglePopover()
    }
    dropView.onDropFiles = { [weak self] urls in
      self?.store.addFiles(urls: urls)
    }
    dropView.onHighlightChange = { [weak button] isHighlighted in
      // ドラッグ中はボタンをハイライトしてフィードバックする.
      button?.highlight(isHighlighted)
    }
    button.addSubview(dropView)
  }

  /// ポップオーバーへ SwiftUI 製の一覧 UI を載せる.
  private func configurePopover() {
    popover.behavior = .transient
    popover.animates = true
    popover.contentSize = NSSize(width: 300, height: 400)
    popover.contentViewController = NSHostingController(
      rootView: PopoverView(store: store, loginManager: loginManager)
    )
  }

  // MARK: - ポップオーバー制御

  /// ポップオーバーの表示/非表示を切り替える.
  private func togglePopover() {
    if popover.isShown {
      popover.performClose(nil)
    } else {
      guard let button = statusItem.button else { return }
      popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
      // ポップオーバー内の操作を受け付けられるようキーウインドウにする.
      popover.contentViewController?.view.window?.makeKey()
    }
  }
}

/// メニューバーアイコン上でのドラッグ＆ドロップとクリックを扱うビュー.
final class StatusDropView: NSView {
  /// クリック(マウスダウン)時に呼ばれる.
  var onClick: (() -> Void)?
  /// ファイルがドロップされたときに URL 群を渡す.
  var onDropFiles: (([URL]) -> Void)?
  /// ドラッグ中のハイライト状態変化を通知する.
  var onHighlightChange: ((Bool) -> Void)?

  override init(frame frameRect: NSRect) {
    super.init(frame: frameRect)
    // ファイル URL のドラッグを受け付けるよう登録する.
    registerForDraggedTypes([.fileURL])
  }

  required init?(coder: NSCoder) {
    fatalError("init(coder:) はサポートしていません")
  }

  // クリックでポップオーバーを開閉する.
  override func mouseDown(with event: NSEvent) {
    onClick?()
  }

  // ファイルがアイコン上へ入ってきたとき.
  override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
    onHighlightChange?(true)
    return .copy
  }

  // ドラッグがアイコンから外れたとき.
  override func draggingExited(_ sender: NSDraggingInfo?) {
    onHighlightChange?(false)
  }

  // 実際にドロップされたときの処理.
  override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
    let pasteboard = sender.draggingPasteboard
    let options: [NSPasteboard.ReadingOptionKey: Any] = [
      .urlReadingFileURLsOnly: true
    ]

    guard
      let urls = pasteboard.readObjects(
        forClasses: [NSURL.self],
        options: options
      ) as? [URL],
      !urls.isEmpty
    else {
      return false
    }

    onDropFiles?(urls)
    return true
  }

  // ドラッグ操作の終了時にハイライトを解除する.
  override func draggingEnded(_ sender: NSDraggingInfo) {
    onHighlightChange?(false)
  }
}
