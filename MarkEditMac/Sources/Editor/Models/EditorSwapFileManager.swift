//
//  EditorSwapFileManager.swift
//  MarkEditMac
//
//  Created on 2026-05-24.
//

import AppKit
import CryptoKit

/**
 Manages swap files for crash recovery, similar to Vim's .swp files.

 Swap files are written on a debounced schedule after each edit and
 cleaned up on successful save or close. On app launch, orphaned swap
 files are detected and the user is offered a chance to recover them.
 */
final class EditorSwapFileManager {
  static let shared = EditorSwapFileManager()

  private let swapDirectory: URL
  private let debounceInterval: TimeInterval = 5.0
  private let ioQueue = DispatchQueue(label: "com.markedit.swapfile", qos: .utility)

  private struct PendingWrite {
    let swapURL: URL
    var task: Task<Void, Never>?
  }

  private var pendingWrites: [String: PendingWrite] = [:]
  private let lock = NSLock()

  private init() {
    let appSupport = FileManager.default.urls(
      for: .applicationSupportDirectory, in: .userDomainMask
    ).first ?? FileManager.default.temporaryDirectory

    swapDirectory = appSupport
      .appendingPathComponent("MarkEdit", isDirectory: true)
      .appendingPathComponent("swap", isDirectory: true)

    try? FileManager.default.createDirectory(at: swapDirectory, withIntermediateDirectories: true)
  }

  // MARK: - Public API

  /// Schedule a debounced swap file write. The content provider is called when the debounce fires.
  func scheduleWrite(
    key: String,
    fileURL: URL?,
    contentProvider: @escaping () async -> String?
  ) {
    let swapURL = swapFileURL(for: key)

    lock.lock()
    defer { lock.unlock() }

    // Cancel any previously scheduled write for this key
    pendingWrites[key]?.task?.cancel()

    let task = Task { [weak self] in
      try? await Task.sleep(for: .seconds(self?.debounceInterval ?? 5))

      guard let self, !Task.isCancelled else { return }

      if let content = await contentProvider() {
        self.writeSwapFile(at: swapURL, fileURL: fileURL, content: content)
      }
    }

    pendingWrites[key] = PendingWrite(swapURL: swapURL, task: task)
  }

  /// Immediately flush content to the swap file, cancelling any pending debounced write.
  func flushWrite(key: String, fileURL: URL?, content: String) {
    let swapURL = swapFileURL(for: key)

    lock.lock()
    pendingWrites[key]?.task?.cancel()
    pendingWrites.removeValue(forKey: key)
    lock.unlock()

    writeSwapFile(at: swapURL, fileURL: fileURL, content: content)
  }

  /// Remove the swap file for a document (called on clean save or close).
  func removeSwapFile(key: String) {
    let swapURL = swapFileURL(for: key)

    lock.lock()
    pendingWrites[key]?.task?.cancel()
    pendingWrites.removeValue(forKey: key)
    lock.unlock()

    try? FileManager.default.removeItem(at: swapURL)
  }

  /// Scan for orphaned swap files on launch. Returns info sorted by timestamp (newest first).
  func checkForOrphanedSwapFiles() -> [SwapFileInfo] {
    guard let fileURLs = try? FileManager.default.contentsOfDirectory(
      at: swapDirectory,
      includingPropertiesForKeys: [.contentModificationDateKey],
      options: .skipsHiddenFiles
    ) else {
      return []
    }

    return fileURLs
      .compactMap { url in
        guard let info = readSwapFile(at: url) else { return nil }
        return info
      }
      .sorted { $0.timestamp > $1.timestamp }
  }

  /// Find a swap file whose originalPath matches the given file path.
  /// Returns the content if the swap file timestamp is newer than `fileModificationDate`.
  func newerSwapContent(for filePath: String, fileModificationDate: Date) -> String? {
    guard let fileURLs = try? FileManager.default.contentsOfDirectory(
      at: swapDirectory,
      includingPropertiesForKeys: nil,
      options: .skipsHiddenFiles
    ) else {
      return nil
    }

    for url in fileURLs {
      guard let info = readSwapFile(at: url),
            info.originalPath == filePath,
            info.timestamp > fileModificationDate else {
        continue
      }
      // Found a swap file with newer content — remove it since we're recovering now
      try? FileManager.default.removeItem(at: url)
      return info.content
    }

    return nil
  }

  /// Read and parse a specific swap file for recovery.
  func recoverSwapFile(at url: URL) -> SwapFileInfo? {
    readSwapFile(at: url)
  }

  /// Delete a specific swap file (user chose to discard recovery).
  func discardSwapFile(at url: URL) {
    try? FileManager.default.removeItem(at: url)
  }

  /// Remove all swap files (for manual cleanup).
  func removeAllSwapFiles() {
    lock.lock()
    for (_, pending) in pendingWrites {
      pending.task?.cancel()
    }
    pendingWrites.removeAll()
    lock.unlock()

    if let fileURLs = try? FileManager.default.contentsOfDirectory(
      at: swapDirectory, includingPropertiesForKeys: nil
    ) {
      for url in fileURLs {
        try? FileManager.default.removeItem(at: url)
      }
    }
  }

  /// Generate a stable key for untitled documents (caller should store this on the document).
  static func generateSwapFileKey() -> String {
    UUID().uuidString
  }
}

// MARK: - Private

private extension EditorSwapFileManager {
  func swapFileURL(for key: String) -> URL {
    let hash = SHA256.hash(data: Data(key.utf8))
    let hexName = hash.compactMap { String(format: "%02x", $0) }.joined()
    return swapDirectory.appendingPathComponent("\(hexName).json")
  }

  func writeSwapFile(at url: URL, fileURL: URL?, content: String) {
    ioQueue.async {
      let info = SwapFileInfo(
        swapURL: url,
        originalPath: fileURL?.absoluteURL.path,
        timestamp: Date(),
        content: content
      )

      let encoder = JSONEncoder()
      encoder.outputFormatting = .sortedKeys
      guard let data = try? encoder.encode(info) else { return }
      try? data.write(to: url, options: .atomic)
    }
  }

  func readSwapFile(at url: URL) -> SwapFileInfo? {
    guard let data = try? Data(contentsOf: url) else { return nil }
    let decoder = JSONDecoder()
    return try? decoder.decode(SwapFileInfo.self, from: data)
  }
}

// MARK: - SwapFileInfo

struct SwapFileInfo: Codable {
  let swapURL: URL
  let originalPath: String?
  let timestamp: Date
  let content: String

  enum CodingKeys: String, CodingKey {
    case originalPath
    case timestamp
    case content
  }

  init(swapURL: URL, originalPath: String?, timestamp: Date, content: String) {
    self.swapURL = swapURL
    self.originalPath = originalPath
    self.timestamp = timestamp
    self.content = content
  }

  init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    originalPath = try container.decodeIfPresent(String.self, forKey: .originalPath)
    timestamp = try container.decode(Date.self, forKey: .timestamp)
    content = try container.decode(String.self, forKey: .content)
    swapURL = URL(fileURLWithPath: "") // Set by caller after reading from disk
  }

  func encode(to encoder: Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    try container.encodeIfPresent(originalPath, forKey: .originalPath)
    try container.encode(timestamp, forKey: .timestamp)
    try container.encode(content, forKey: .content)
  }

  var suggestedFilename: String {
    if let path = originalPath {
      return URL(fileURLWithPath: path).lastPathComponent
    }
    return "Untitled.md"
  }

  var relativeTimeDescription: String {
    let interval = Date.now.timeIntervalSince(timestamp)
    switch interval {
    case ..<60:
      return String(localized: "just now")
    case ..<3600:
      let minutes = Int(interval / 60)
      return String(localized: "\(minutes)m ago")
    case ..<86400:
      let hours = Int(interval / 3600)
      return String(localized: "\(hours)h ago")
    default:
      let days = Int(interval / 86400)
      return String(localized: "\(days)d ago")
    }
  }
}
