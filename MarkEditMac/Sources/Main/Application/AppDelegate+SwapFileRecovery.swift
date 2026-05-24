//
//  AppDelegate+SwapFileRecovery.swift
//  MarkEditMac
//
//  Created on 2026-05-24.
//

import AppKit

extension AppDelegate {
  /// Check for orphaned swap files and offer recovery if any are found.
  func checkForSwapFileRecovery() {
    let orphans = EditorSwapFileManager.shared.checkForOrphanedSwapFiles()
    guard !orphans.isEmpty else { return }

    // Show a single alert for the most recent swap file.
    // If there are multiple, the user can recover them one at a time by re-launching,
    // which is simpler than a custom multi-select panel.
    showSwapFileRecoveryAlert(for: orphans)
  }

  private func showSwapFileRecoveryAlert(for orphans: [SwapFileInfo]) {
    guard let first = orphans.first else { return }

    let alert = NSAlert()
    alert.messageText = String(localized: "Recover unsaved changes?")
    alert.informativeText = String(localized: "MarkEdit found an unsaved file from a previous session.\n\n\(first.suggestedFilename) — edited \(first.relativeTimeDescription)")
    alert.alertStyle = .warning
    alert.addButton(withTitle: String(localized: "Recover"))
    alert.addButton(withTitle: String(localized: "Discard"))

    // Show as a non-modal alert to not block app launch
    guard let window = NSApp.windows.first(where: { $0 is EditorWindow }) ?? NSApp.windows.first else {
      // No window available yet, try again shortly
      DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
        self?.showSwapFileRecoveryAlert(for: orphans)
      }
      return
    }

    alert.beginSheetModal(for: window) { [weak self] response in
      guard let self else { return }

      if response == .alertFirstButtonReturn {
        self.recoverSwapFile(first)
      } else {
        EditorSwapFileManager.shared.discardSwapFile(at: first.swapURL)
      }

      // Show next orphan if any
      let remaining = Array(orphans.dropFirst())
      if !remaining.isEmpty {
        DispatchQueue.main.async {
          self.showSwapFileRecoveryAlert(for: remaining)
        }
      }
    }
  }

  private func recoverSwapFile(_ info: SwapFileInfo) {
    let filename = info.suggestedFilename
    let content = info.content

    // Create a new untitled document with the recovered content
    AppDocumentController.suggestedFilename = filename
    NSDocumentController.shared.newDocument(nil)

    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
      self?.currentEditor?.prepareInitialContent(content)
    }

    // Remove the swap file since it's been recovered
    EditorSwapFileManager.shared.discardSwapFile(at: info.swapURL)
  }
}
