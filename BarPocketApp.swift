//
//  BarPocketApp.swift
//  BarPocket
//
//  一時ファイル置き場アプリのエントリポイント.
//  Dock に出る通常ウインドウ(GUI)と, メニューバー常駐の両方を提供する.
//

import SwiftUI

@main
struct BarPocketApp: App {
  // AppKit のライフサイクル(NSStatusItem 等)を扱うため AppDelegate を接続する.
  @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

  var body: some Scene {
    // Dock に出る通常のメインウインドウ.
    // ストアと自動起動マネージャはメニューバー側と共有する.
    WindowGroup("BarPocket") {
      MainView(store: appDelegate.store, loginManager: appDelegate.loginManager)
    }
    .windowResizability(.contentMinSize)
  }
}

/// アプリ全体のライフサイクルを管理するデリゲート.
final class AppDelegate: NSObject, NSApplicationDelegate {
  // ウインドウとメニューバーで共有するモデル/設定.
  let store = FileStore()
  let loginManager = LoginItemManager()

  // メニューバーのアイコンとポップオーバーを統括するコントローラ.
  private var statusItemController: StatusItemController?

  func applicationDidFinishLaunching(_ notification: Notification) {
    // Dock に出る通常アプリ + メニューバー常駐の両対応.
    NSApp.setActivationPolicy(.regular)

    // メニューバー常駐をセットアップする.
    statusItemController = StatusItemController(
      store: store,
      loginManager: loginManager
    )
  }

  /// ウインドウをすべて閉じてもアプリを終了させない(常駐を維持する).
  func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
    false
  }

  /// Dock アイコンをクリックしたとき, ウインドウが無ければ再表示する.
  func applicationShouldHandleReopen(
    _ sender: NSApplication,
    hasVisibleWindows: Bool
  ) -> Bool {
    true
  }
}
