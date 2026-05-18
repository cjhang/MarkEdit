//
//  AppDelegate+Menu.swift
//  MarkEditMac
//
//  Created by cyan on 1/15/23.
//

import AppKit
import MarkEditKit

extension AppDelegate: NSMenuDelegate {
  func menuNeedsUpdate(_ menu: NSMenu) {
    switch menu {
    case mainFileMenu:
      reconfigureMainFileMenu(document: currentDocument)
    case mainEditMenu:
      reconfigureMainEditMenu(document: currentDocument)
    case mainExtensionsMenu:
      reconfigureMainExtensionsMenu(document: currentDocument)
    case mainWindowMenu:
      reconfigureMainWindowMenu(document: currentDocument)
    case openFileInMenu:
      reconfigureOpenFileInMenu(document: currentDocument)
    case reopenFileMenu:
      reconfigureReopenFileMenu(document: currentDocument)
    case lineEndingsMenu:
      reconfigureLineEndingsMenu(document: currentDocument)
    default:
      break
    }
  }
}

// MARK: - Private

private extension AppDelegate {
  func reconfigureMainFileMenu(document: EditorDocument?) {
    [openFileInMenu, reopenFileMenu, lineEndingsMenu].forEach {
      $0?.superMenuItem?.isEnabled = document?.fileURL != nil
    }

    fileFromClipboardItem?.isEnabled = NSPasteboard.general.hasText
  }

  func reconfigureMainEditMenu(document: EditorDocument?) {
    Task { @MainActor in
      guard let document else {
        return
      }

      editUndoItem?.isEnabled = await document.canUndo
      editRedoItem?.isEnabled = await document.canRedo
      editPasteItem?.isEnabled = NSPasteboard.general.hasText
    }

    editTypewriterItem?.setOn(AppPreferences.Editor.typewriterMode)
  }

  func reconfigureMainExtensionsMenu(document: EditorDocument?) {
    mainExtensionsMenu?.items.forEach {
      let isEnabled = $0.target === NSApp.appDelegate || document != nil
      $0.setEnabledRecursively(isEnabled: isEnabled)
    }
  }

  func reconfigureMainWindowMenu(document: EditorDocument?) {
    windowFloatingItem?.isEnabled = NSApp.keyWindow is EditorWindow
    windowFloatingItem?.setOn(NSApp.keyWindow?.level == .floating)

    let goToTabPrefix = "goToTab_"
    let tabCount = NSApp.keyWindow?.tabGroup?.windows.count ?? 0

    // Remove existing Go to Tab items
    mainWindowMenu?.items
      .filter { $0.identifier?.rawValue.hasPrefix(goToTabPrefix) == true }
      .forEach { mainWindowMenu?.removeItem($0) }

    // Find insertion point: before the first custom item (Minimize). macOS puts
    // system-provided tab items at the top, so inserting at the first custom item
    // places "Go to Tab" items right after the system tab items.
    let insertIndex = mainWindowMenu?.items.firstIndex {
      $0.action == #selector(NSWindow.performMiniaturize(_:))
    } ?? 0

    guard tabCount > 1, let menu = mainWindowMenu else { return }

    // Add in reverse order so they appear as Tab 1, Tab 2, ... Tab N
    for tabIndex in (1...min(tabCount, 6)).reversed() {
      let item = NSMenuItem(
        title: String(format: Localized.Window.goToTab, tabIndex),
        action: nil,
        keyEquivalent: "\(tabIndex)"
      )
      item.identifier = NSUserInterfaceItemIdentifier("\(goToTabPrefix)\(tabIndex)")
      item.tag = tabIndex
      item.target = NSApp.appDelegate
      item.action = #selector(AppDelegate.goToTab(_:))
      menu.insertItem(item, at: insertIndex)
    }

    // Add a separator between Go to Tab items and Minimize
    if tabCount > 1 {
      let separator = NSMenuItem.separator()
      separator.identifier = NSUserInterfaceItemIdentifier("\(goToTabPrefix)separator")
      menu.insertItem(separator, at: insertIndex)
    }
  }

  @MainActor
  func reconfigureOpenFileInMenu(document: EditorDocument?) {
    openFileInMenu?.removeAllItems()

    // Disabled or not able to find the document, just leave the menu empty
    guard let fileURL = document?.fileURL else {
      return
    }

    // Basically, we wouldn't expect to see "MarkEdit.app"
    let appURLs = NSWorkspace.shared.urlsForApplications(toOpen: fileURL).filter {
      $0.lastPathComponent != Bundle.main.bundleURL.lastPathComponent
    }

    appURLs.forEach { appURL in
      let item = openFileInMenu?.addItem(withTitle: appURL.localizedName) {
        NSWorkspace.shared.open(
          [fileURL],
          withApplicationAt: appURL,
          configuration: NSWorkspace.OpenConfiguration(),
          completionHandler: nil
        )
      }

      let icon = NSWorkspace.shared.icon(forFile: appURL.path)
      item?.image = icon.resized(with: CGSize(width: 16, height: 16))
    }
  }

  func reconfigureReopenFileMenu(document: EditorDocument?) {
    reopenFileMenu?.removeAllItems()

    // Disabled or not able to find the document, just leave the menu empty
    guard document?.fileURL != nil else {
      return
    }

    for encoding in EditorTextEncoding.allCases {
      let item = reopenFileMenu?.addItem(withTitle: encoding.description, action: #selector(EditorViewController.reopenWithEncoding(_:)))
      item?.representedObject = encoding

      if EditorTextEncoding.groupingCases.contains(encoding) {
        reopenFileMenu?.addItem(.separator())
      }
    }
  }

  func reconfigureLineEndingsMenu(document: EditorDocument?) {
    Task { @MainActor in
      guard let lineEndings = await document?.lineEndings else {
        return
      }

      lineEndingsLFItem?.setOn(lineEndings == .lf)
      lineEndingsCRLFItem?.setOn(lineEndings == .crlf)
      lineEndingsCRItem?.setOn(lineEndings == .cr)
      lineEndingsMenu?.reloadItems()
    }
  }
}

// MARK: - Tab Switching

extension AppDelegate {
  @objc func goToTab(_ sender: Any?) {
    guard let index = (sender as? NSMenuItem)?.tag, index > 0 else { return }
    guard let window = NSApp.keyWindow, let tabGroup = window.tabGroup else { return }
    let windows = tabGroup.windows
    guard index <= windows.count else { return }
    tabGroup.selectedWindow = windows[index - 1]
    windows[index - 1].makeKeyAndOrderFront(nil)
  }
}

// MARK: - Private

private extension AppDelegate {
  @IBAction func checkForUpdates(_ sender: Any?) {
    Task {
      await AppUpdater.checkForUpdates(explicitly: true)
    }
  }

  @IBAction func openDocumentsFolder(_ sender: Any?) {
    NSWorkspace.shared.open(.documentsDirectory)
  }

  @IBAction func grantFolderAccess(_ sender: Any?) {
    NSApp.closeOpenPanels()
    Task {
      await saveGrantedFolderAsBookmark()
    }
  }

  @IBAction func newFileFromClipboard(_ sender: Any?) {
    createNewFile(initialContent: NSPasteboard.general.string)
  }

  @IBAction func saveAllDocuments(_ sender: Any?) {
    NSDocumentController.shared.saveAllDocuments(nil)
  }

  @IBAction func openDevelopmentGuide(_ sender: Any?) {
    NSWorkspace.shared.safelyOpenURL(string: "https://github.com/MarkEdit-app/MarkEdit/wiki/Development")
  }

  @IBAction func openOfficialExtensions(_ sender: Any?) {
    NSWorkspace.shared.safelyOpenURL(string: "https://github.com/MarkEdit-app/MarkEdit/wiki/Extensions")
  }

  @IBAction func openCustomizationGuide(_ sender: Any?) {
    NSWorkspace.shared.safelyOpenURL(string: "https://github.com/MarkEdit-app/MarkEdit/wiki/Customization")
  }

  @IBAction func showHelp(_ sender: Any?) {
    NSWorkspace.shared.safelyOpenURL(string: "https://github.com/MarkEdit-app/MarkEdit/wiki")
  }

  @IBAction func openIssueTracker(_ sender: Any?) {
    NSWorkspace.shared.safelyOpenURL(string: "https://github.com/MarkEdit-app/MarkEdit/issues")
  }

  @IBAction func openVersionHistory(_ sender: Any?) {
    NSWorkspace.shared.safelyOpenURL(string: "https://github.com/MarkEdit-app/MarkEdit/releases")
  }
}
