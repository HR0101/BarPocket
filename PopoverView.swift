//
//  PopoverView.swift
//  BarPocket
//
//  ファイル一覧と設定をまとめた SwiftUI ビュー.
//  共通ビュー StashContentView を, メインウインドウ(MainView)と
//  メニューバーのポップオーバー(PopoverView)の両方で再利用する.
//

import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// 一覧・設定をまとめた共通コンテンツ.
struct StashContentView: View {
  @ObservedObject var store: FileStore
  @ObservedObject var loginManager: LoginItemManager
  // ファイルをドロップ中かどうか(枠のハイライト用).
  @State private var isDropTargeted = false

  var body: some View {
    VStack(spacing: 0) {
      header
      Divider()
      // 保持ファイルが無ければ案内, あれば一覧を表示する.
      if store.items.isEmpty {
        emptyState
      } else {
        fileList
      }
      Divider()
      footer
    }
    // ドロップ中はアクセントカラーの枠を表示する.
    .overlay(
      RoundedRectangle(cornerRadius: 8)
        .strokeBorder(Color.accentColor, lineWidth: isDropTargeted ? 3 : 0)
        .padding(1)
        .allowsHitTesting(false)
    )
    // 表示のたびに最新の登録状態へ更新する.
    .onAppear {
      loginManager.refresh()
    }
    // ⌘C で選択中の項目をクリップボードへコピーする(リストには残る).
    .onCopyCommand {
      let targets = store.selectedItems
      guard !targets.isEmpty else { return [] }
      return targets.compactMap { NSItemProvider(contentsOf: $0.url) }
    }
    // ウインドウ/ポップオーバーへのファイルドロップで追加する.
    .onDrop(of: [.fileURL], isTargeted: $isDropTargeted) { providers in
      handleDrop(providers)
    }
  }

  // MARK: - 各パーツ

  /// 上部のタイトル・件数・全選択/クリアボタン.
  private var header: some View {
    HStack(spacing: 8) {
      Image(systemName: "archivebox")
      Text("BarPocket")
        .font(.headline)
      Spacer()
      // 選択中はその件数を, それ以外は総件数を表示する.
      if store.selection.isEmpty {
        Text("\(store.items.count) 件")
          .font(.callout)
          .foregroundStyle(.secondary)
      } else {
        Text("\(store.selection.count) 件選択")
          .font(.callout)
          .foregroundStyle(.secondary)
      }
      // 全選択 / 選択解除を切り替えるボタン.
      Button {
        toggleSelectAll()
      } label: {
        Image(systemName: isAllSelected ? "checklist.checked" : "checklist")
      }
      .buttonStyle(.borderless)
      .disabled(store.items.isEmpty)
      .help(isAllSelected ? "選択を解除" : "すべて選択")
      // 手動でリストを空にするボタン.
      Button {
        store.clearAll()
      } label: {
        Image(systemName: "trash")
      }
      .buttonStyle(.borderless)
      .disabled(store.items.isEmpty)
      .help("リストを空にする")
    }
    .padding(.horizontal, 12)
    .padding(.vertical, 8)
  }

  /// 下部の設定(自動起動トグル)と操作ヒント.
  private var footer: some View {
    VStack(spacing: 8) {
      // ログイン時に自動起動するかどうかのトグル.
      Toggle(isOn: loginItemBinding) {
        Label("ログイン時に起動", systemImage: "power")
          .font(.callout)
      }
      .toggleStyle(.switch)
      .controlSize(.small)

      // 承認待ちや失敗時のメッセージ.
      if let message = loginManager.statusMessage {
        Text(message)
          .font(.caption2)
          .foregroundStyle(.orange)
          .frame(maxWidth: .infinity, alignment: .leading)
      }

      // 項目があるときだけ操作ヒントを表示する.
      if !store.items.isEmpty {
        VStack(spacing: 2) {
          Text("クリックで選択 ・ ⌘/⇧で複数選択")
          Text("ドラッグで取り出し（消える） ・ コピーで複製（残す）")
        }
        .font(.caption2)
        .foregroundStyle(.secondary)
        .multilineTextAlignment(.center)
        .frame(maxWidth: .infinity)
      }

      // アプリを終了するボタン(メニューの ⌘Q でも終了可能).
      HStack {
        Spacer()
        Button {
          NSApplication.shared.terminate(nil)
        } label: {
          Label("BarPocket を終了", systemImage: "power")
            .font(.caption)
        }
        .buttonStyle(.borderless)
        .controlSize(.small)
        .foregroundStyle(.secondary)
        .help("常駐を終了する")
      }
    }
    .padding(.horizontal, 12)
    .padding(.vertical, 8)
  }

  /// 空のときの案内表示.
  private var emptyState: some View {
    VStack(spacing: 10) {
      Spacer()
      Image(systemName: "tray.and.arrow.down")
        .font(.system(size: 40))
        .foregroundStyle(.secondary)
      Text("ここ、またはメニューバーのアイコンへ\nファイルをドラッグ＆ドロップ")
        .multilineTextAlignment(.center)
        .font(.callout)
        .foregroundStyle(.secondary)
      Spacer()
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
  }

  /// 保持ファイルの一覧.
  private var fileList: some View {
    ScrollView {
      LazyVStack(spacing: 0) {
        ForEach(store.items) { item in
          FileRowView(item: item, store: store)
          Divider()
        }
      }
    }
  }

  // MARK: - ドロップ処理

  /// ドロップされた項目からファイル URL を取り出してストックへ追加する.
  private func handleDrop(_ providers: [NSItemProvider]) -> Bool {
    var handled = false
    for provider in providers where provider.canLoadObject(ofClass: URL.self) {
      handled = true
      _ = provider.loadObject(ofClass: URL.self) { url, _ in
        guard let url, url.isFileURL else { return }
        // UI 更新はメインスレッドで行う.
        DispatchQueue.main.async {
          store.addFiles(urls: [url])
        }
      }
    }
    return handled
  }

  // MARK: - 設定/選択補助

  /// 自動起動トグル用のバインディング.
  private var loginItemBinding: Binding<Bool> {
    Binding(
      get: { loginManager.isEnabled },
      set: { loginManager.setEnabled($0) }
    )
  }

  /// すべての項目が選択済みかどうか.
  private var isAllSelected: Bool {
    !store.items.isEmpty && store.selection.count == store.items.count
  }

  /// 全選択と全解除を切り替える.
  private func toggleSelectAll() {
    if isAllSelected {
      store.clearSelection()
    } else {
      store.selectAll()
    }
  }
}

/// メインウインドウ用のラッパー.
struct MainView: View {
  let store: FileStore
  let loginManager: LoginItemManager

  var body: some View {
    StashContentView(store: store, loginManager: loginManager)
      .frame(minWidth: 360, idealWidth: 380, minHeight: 480, idealHeight: 560)
  }
}

/// メニューバーのポップオーバー用のラッパー.
struct PopoverView: View {
  let store: FileStore
  let loginManager: LoginItemManager

  var body: some View {
    StashContentView(store: store, loginManager: loginManager)
      .frame(width: 340, height: 460)
  }
}

/// 一覧の 1 行を表すビュー.
struct FileRowView: View {
  let item: StashItem
  @ObservedObject var store: FileStore

  var body: some View {
    HStack(spacing: 10) {
      // アイコンとファイル名の領域だけをドラッグ取り出し可能にする.
      HStack(spacing: 10) {
        Image(nsImage: store.icon(for: item))
          .resizable()
          .frame(width: 28, height: 28)
        VStack(alignment: .leading, spacing: 2) {
          Text(item.name)
            .lineLimit(1)
            .truncationMode(.middle)
          Text(store.fileSizeString(for: item))
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        Spacer(minLength: 0)
      }
      .contentShape(Rectangle())
      // 透明なドラッグ元ビューを重ね, クリック選択と一括取り出しを処理する.
      .overlay(
        FileDragView(item: item, store: store)
      )

      // コピーボタン(ドラッグ領域の外側に配置). コピーしてもリストには残る.
      Button {
        store.copyToPasteboard(activatedBy: item)
      } label: {
        Image(systemName: "doc.on.doc")
          .foregroundStyle(.secondary)
      }
      .buttonStyle(.borderless)
      .help("コピー（リストに残す）")

      // 個別削除ボタン(ドラッグ領域の外側に配置).
      Button {
        store.remove(item)
      } label: {
        Image(systemName: "xmark.circle.fill")
          .foregroundStyle(.secondary)
      }
      .buttonStyle(.borderless)
      .help("この項目を削除")
    }
    .padding(.horizontal, 12)
    .padding(.vertical, 6)
    // 選択中の行をハイライト表示する.
    .background(
      store.isSelected(item)
        ? Color.accentColor.opacity(0.18)
        : Color.clear
    )
  }
}
