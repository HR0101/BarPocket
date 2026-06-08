//
//  LoginItemManager.swift
//  BarPocket
//
//  「ログイン時に自動起動」を管理するクラス.
//  macOS 13 以降の SMAppService を用いて, アプリ自身をログイン項目に登録/解除する.
//

import Combine
import ServiceManagement
import SwiftUI

/// ログイン項目への登録状態を管理する.
final class LoginItemManager: ObservableObject {
  /// 現在ログイン項目として有効かどうか.
  @Published private(set) var isEnabled: Bool = false
  /// 失敗や承認待ちなどをユーザーへ伝えるためのメッセージ.
  @Published private(set) var statusMessage: String?

  /// このアプリ本体を表すサービス.
  private let service = SMAppService.mainApp

  init() {
    refresh()
  }

  /// 現在の登録状態を読み直す.
  func refresh() {
    isEnabled = (service.status == .enabled)

    // システム設定での承認待ちの場合は案内を出す.
    if service.status == .requiresApproval {
      statusMessage = "システム設定のログイン項目で許可してください"
    } else {
      statusMessage = nil
    }
  }

  /// 自動起動の有効/無効を切り替える.
  func setEnabled(_ enabled: Bool) {
    do {
      if enabled {
        // すでに有効な場合の二重登録を避ける.
        if service.status != .enabled {
          try service.register()
        }
      } else {
        try service.unregister()
      }
      statusMessage = nil
    } catch {
      // 失敗時はログを残し, 状態表示を更新する.
      NSLog("BarPocket: ログイン項目の変更に失敗しました - \(error.localizedDescription)")
      statusMessage = "設定の変更に失敗しました"
    }

    // 実際の登録状態を反映させる.
    refresh()
  }
}
