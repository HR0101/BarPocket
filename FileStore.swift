//
//  FileStore.swift
//  BarPocket
//
//  保持しているファイルの一覧を管理するモデル.
//  ドロップされたファイルはアプリ専用のストック用ディレクトリへ移動して保持する.
//

import AppKit
import Combine
import SwiftUI

/// ストックされた 1 ファイルを表すモデル.
struct StashItem: Identifiable, Equatable {
  let id = UUID()
  /// ストック用ディレクトリ内に移動された実体のパス.
  let url: URL

  /// 表示用のファイル名.
  var name: String {
    url.lastPathComponent
  }

  /// URL が一致すれば同一とみなす.
  static func == (lhs: StashItem, rhs: StashItem) -> Bool {
    lhs.url == rhs.url
  }
}

/// 保持ファイルの追加・取り出し・クリアを担当するストア.
/// 画面更新のため ObservableObject として実装する.
final class FileStore: ObservableObject {
  /// 現在保持しているファイル一覧(読み取り専用で公開).
  @Published private(set) var items: [StashItem] = []

  /// 現在選択中の項目 id 集合(複数選択・一括取り出し用).
  @Published private(set) var selection: Set<UUID> = []

  /// 範囲選択(⇧クリック)の起点となる項目 id.
  private var selectionAnchorID: UUID?

  /// ファイル実体を移動して保持するためのディレクトリ.
  private let stashDirectory: URL

  init() {
    let fileManager = FileManager.default
    // Application Support 配下に専用フォルダを確保する.
    // 取得に失敗した場合は一時ディレクトリへフォールバックする.
    let baseDirectory = (try? fileManager.url(
      for: .applicationSupportDirectory,
      in: .userDomainMask,
      appropriateFor: nil,
      create: true
    )) ?? fileManager.temporaryDirectory

    stashDirectory = baseDirectory
      .appendingPathComponent("BarPocket", isDirectory: true)
      .appendingPathComponent("Stash", isDirectory: true)

    createStashDirectoryIfNeeded()
    loadExistingFiles()
  }

  // MARK: - 公開メソッド

  /// 複数ファイルをストックへ追加する.
  func addFiles(urls: [URL]) {
    for url in urls {
      moveIntoStash(url)
    }
  }

  /// 指定した項目をストックから取り除く.
  func remove(_ item: StashItem, permanently: Bool = false) {
    deleteFile(at: item.url, permanently: permanently)
    items.removeAll { $0.id == item.id }
    selection.remove(item.id)
    removeOriginalURL(for: item.url)
  }

  /// 指定した項目を元の場所へ戻す (Xボタン用).
  func restore(_ item: StashItem) {
    if let originalPath = getOriginalURL(for: item.url) {
      do {
        // 元の場所へ移動. 同名ファイルがある場合はリネームして衝突回避.
        var destination = originalPath
        var index = 1
        let baseName = (originalPath.lastPathComponent as NSString).deletingPathExtension
        let pathExtension = (originalPath.lastPathComponent as NSString).pathExtension
        let parentDir = originalPath.deletingLastPathComponent()

        while FileManager.default.fileExists(atPath: destination.path) {
          let newName = pathExtension.isEmpty ? "\(baseName) \(index)" : "\(baseName) \(index).\(pathExtension)"
          destination = parentDir.appendingPathComponent(newName)
          index += 1
        }

        try FileManager.default.moveItem(at: item.url, to: destination)
        items.removeAll { $0.id == item.id }
        selection.remove(item.id)
        removeOriginalURL(for: item.url)
        return
      } catch {
        NSLog("BarPocket: 元の場所への復元に失敗しました - \(error.localizedDescription)")
      }
    }
    
    // オリジナルのパスが不明、または移動に失敗した場合はデスクトップへ移動する
    do {
      let desktop = try FileManager.default.url(for: .desktopDirectory, in: .userDomainMask, appropriateFor: nil, create: false)
      let destination = desktop.appendingPathComponent(item.url.lastPathComponent)
      
      // デスクトップで同名ファイルがある場合
      var finalDestination = destination
      var index = 1
      let baseName = (destination.lastPathComponent as NSString).deletingPathExtension
      let pathExtension = (destination.lastPathComponent as NSString).pathExtension
      while FileManager.default.fileExists(atPath: finalDestination.path) {
        let newName = pathExtension.isEmpty ? "\(baseName) \(index)" : "\(baseName) \(index).\(pathExtension)"
        finalDestination = desktop.appendingPathComponent(newName)
        index += 1
      }
      
      try FileManager.default.moveItem(at: item.url, to: finalDestination)
      items.removeAll { $0.id == item.id }
      selection.remove(item.id)
      removeOriginalURL(for: item.url)
    } catch {
      NSLog("BarPocket: デスクトップへの復元にも失敗しました - \(error.localizedDescription)")
      remove(item) // 最終手段としてゴミ箱へ
    }
  }

  /// 複数項目をまとめてストックから取り除く.
  func removeItems(_ targets: [StashItem], permanently: Bool = false) {
    let ids = Set(targets.map { $0.id })
    for target in targets {
      deleteFile(at: target.url, permanently: permanently)
      removeOriginalURL(for: target.url)
    }
    items.removeAll { ids.contains($0.id) }
    selection.subtract(ids)
  }

  /// すべての項目をクリアする.
  func clearAll(permanently: Bool = false) {
    for item in items {
      deleteFile(at: item.url, permanently: permanently)
      removeOriginalURL(for: item.url)
    }
    items.removeAll()
    clearSelection()
  }

  // MARK: - 選択操作

  /// 指定項目が選択中かどうかを返す.
  func isSelected(_ item: StashItem) -> Bool {
    selection.contains(item.id)
  }

  /// 指定項目のみを単独で選択する.
  func selectSingle(_ item: StashItem) {
    selection = [item.id]
    selectionAnchorID = item.id
  }

  /// 指定項目の選択状態を反転する(⌘クリック相当).
  func toggleSelection(_ item: StashItem) {
    if selection.contains(item.id) {
      selection.remove(item.id)
    } else {
      selection.insert(item.id)
    }
    selectionAnchorID = item.id
  }

  /// 起点から指定項目までを範囲選択する(⇧クリック相当).
  func extendSelection(to item: StashItem) {
    guard
      let anchorID = selectionAnchorID,
      let anchorIndex = items.firstIndex(where: { $0.id == anchorID }),
      let targetIndex = items.firstIndex(where: { $0.id == item.id })
    else {
      selectSingle(item)
      return
    }
    let range = anchorIndex <= targetIndex
      ? anchorIndex...targetIndex
      : targetIndex...anchorIndex
    selection = Set(items[range].map { $0.id })
  }

  /// すべての項目を選択する.
  func selectAll() {
    selection = Set(items.map { $0.id })
    selectionAnchorID = items.first?.id
  }

  /// 選択をすべて解除する.
  func clearSelection() {
    selection.removeAll()
    selectionAnchorID = nil
  }

  /// 現在選択中の項目を items の並び順で返す.
  var selectedItems: [StashItem] {
    items.filter { selection.contains($0.id) }
  }

  /// 操作の対象となる項目群を返す.
  /// 起点の項目が選択中なら選択集合全体を, そうでなければその項目単体を返す.
  func actionTargets(for item: StashItem) -> [StashItem] {
    if selection.contains(item.id) {
      // items の並び順を保ったまま選択中の項目を返す.
      return items.filter { selection.contains($0.id) }
    }
    return [item]
  }

  /// ドラッグ操作の対象となる項目群を返す.
  func dragItems(activatedBy item: StashItem) -> [StashItem] {
    actionTargets(for: item)
  }

  // MARK: - コピー&ペースト

  /// 指定項目(選択中なら選択集合)をクリップボードへコピーする.
  /// コピーは複製操作のため, リストや実体は一切変更しない(消えない).
  func copyToPasteboard(activatedBy item: StashItem) {
    copy(actionTargets(for: item))
  }

  /// 選択中の項目をクリップボードへコピーする(⌘C 用).
  /// コピーされた項目はリストに残る.
  func copySelectionToPasteboard() {
    copy(selectedItems)
  }

  /// 指定した項目群のファイル URL をクリップボードへ書き込む.
  private func copy(_ targets: [StashItem]) {
    guard !targets.isEmpty else { return }
    let pasteboard = NSPasteboard.general
    pasteboard.clearContents()
    pasteboard.writeObjects(targets.map { $0.url as NSURL })
  }

  /// 指定項目のファイルアイコンを返す.
  func icon(for item: StashItem) -> NSImage {
    NSWorkspace.shared.icon(forFile: item.url.path)
  }

  /// 指定項目の表示用ファイルサイズ文字列を返す(フォルダ等は空文字).
  func fileSizeString(for item: StashItem) -> String {
    let keys: Set<URLResourceKey> = [.fileSizeKey, .isDirectoryKey]
    guard let values = try? item.url.resourceValues(forKeys: keys) else {
      return ""
    }
    if values.isDirectory == true {
      return "フォルダ"
    }
    guard let size = values.fileSize else {
      return ""
    }
    return ByteCountFormatter.string(fromByteCount: Int64(size), countStyle: .file)
  }

  // MARK: - 内部処理

  /// ファイルをストック用ディレクトリへ移動して一覧へ追加する.
  private func moveIntoStash(_ source: URL) {
    let fileManager = FileManager.default
    let destination = uniqueDestination(for: source.lastPathComponent)

    // サンドボックス環境で外部から渡された URL へアクセスするための権限取得.
    let needsScopeRelease = source.startAccessingSecurityScopedResource()
    defer {
      if needsScopeRelease {
        source.stopAccessingSecurityScopedResource()
      }
    }

    do {
      // 安全に移動するため、まずコピーを行い、成功した場合のみ元ファイルを削除する.
      try fileManager.copyItem(at: source, to: destination)
      
      do {
        try fileManager.removeItem(at: source)
      } catch {
        // 元ファイルの削除に失敗した場合は、コピー先のファイルを消して完全に元に戻す（ロールバック）
        try? fileManager.removeItem(at: destination)
        throw error
      }

      let item = StashItem(url: destination)
      if !items.contains(item) {
        items.append(item)
      }
      saveOriginalURL(source, for: destination)
    } catch {
      // 移動に失敗した場合は状態を元に戻し、ログを残す.
      NSLog("BarPocket: ファイルの移動に失敗しました - \(error.localizedDescription)")
    }
  }

  /// ファイル名衝突を避けた一意な保存先 URL を生成する.
  private func uniqueDestination(for fileName: String) -> URL {
    let fileManager = FileManager.default
    var candidate = stashDirectory.appendingPathComponent(fileName)

    let baseName = (fileName as NSString).deletingPathExtension
    let pathExtension = (fileName as NSString).pathExtension
    var index = 1

    // 同名ファイルが存在する間, 連番を付与して衝突を回避する.
    while fileManager.fileExists(atPath: candidate.path) {
      let newName: String
      if pathExtension.isEmpty {
        newName = "\(baseName) \(index)"
      } else {
        newName = "\(baseName) \(index).\(pathExtension)"
      }
      candidate = stashDirectory.appendingPathComponent(newName)
      index += 1
    }
    return candidate
  }

  /// ファイル実体を削除（デフォルトはゴミ箱へ移動）する.
  private func deleteFile(at url: URL, permanently: Bool = false) {
    do {
      if permanently {
        try FileManager.default.removeItem(at: url)
      } else {
        try FileManager.default.trashItem(at: url, resultingItemURL: nil)
      }
    } catch {
      NSLog("BarPocket: ファイルの削除に失敗しました - \(error.localizedDescription)")
    }
  }

  /// ストック用ディレクトリが無ければ作成する.
  private func createStashDirectoryIfNeeded() {
    do {
      try FileManager.default.createDirectory(
        at: stashDirectory,
        withIntermediateDirectories: true
      )
    } catch {
      NSLog("BarPocket: ストックフォルダの作成に失敗しました - \(error.localizedDescription)")
    }
  }

  /// 起動時に既存のストックファイルを読み込む(前回終了時の内容を復元).
  private func loadExistingFiles() {
    let fileManager = FileManager.default
    guard let contents = try? fileManager.contentsOfDirectory(
      at: stashDirectory,
      includingPropertiesForKeys: nil,
      options: [.skipsHiddenFiles]
    ) else {
      return
    }
    items = contents
      .sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }
      .map { StashItem(url: $0) }
  }

  // MARK: - Original URL Mapping

  private func saveOriginalURL(_ source: URL, for stashURL: URL) {
    var dict = UserDefaults.standard.dictionary(forKey: "OriginalURLs") as? [String: String] ?? [:]
    dict[stashURL.lastPathComponent] = source.path
    UserDefaults.standard.set(dict, forKey: "OriginalURLs")
  }

  private func getOriginalURL(for stashURL: URL) -> URL? {
    let dict = UserDefaults.standard.dictionary(forKey: "OriginalURLs") as? [String: String] ?? [:]
    if let path = dict[stashURL.lastPathComponent] {
      return URL(fileURLWithPath: path)
    }
    return nil
  }

  private func removeOriginalURL(for stashURL: URL) {
    var dict = UserDefaults.standard.dictionary(forKey: "OriginalURLs") as? [String: String] ?? [:]
    dict.removeValue(forKey: stashURL.lastPathComponent)
    UserDefaults.standard.set(dict, forKey: "OriginalURLs")
  }
}
