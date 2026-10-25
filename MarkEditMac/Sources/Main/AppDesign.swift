//
//  AppDesign.swift
//  MarkEditMac
//
//  Created by cyan on 6/12/25.
//

import AppKit
import AppKitExtensions
import FoundationModels

@MainActor
enum AppDesign {
  /**
    Returns `true` to adopt the new design language in macOS Tahoe.
   */
  static var modernStyle: Bool {
    guard #available(macOS 26.0, *) else {
      return false
    }

    return !AppRuntimeConfig.useClassicInterface
  }

  /**
   Returns `true` to use a customized title bar for the editor.

   It will be enabled as long as macOS Tahoe runs.
   */
  static var modernTitleBar: Bool {
    isMacOSTahoe
  }

  /**
   Returns `true` to gradually add icons to the menu bar.

   It will be enabled as long as macOS Tahoe runs.
   */
  static var menuIconEvolution: Bool {
    isMacOSTahoe
  }

  /**
   Returns `true` to always enable `Show Writing Tools` in macOS Golden Gate.

   [macOS 27] Apple Bug: `Ask Siri` and `Show Writing Tools` are both missing.
   */
  static var forceWritingTools: Bool {
    guard #available(macOS 27.0, *) else {
      return false
    }

    // Don't use NSWritingToolsCoordinator.isWritingToolsAvailable here,
    // it returns `false` when "New Siri" is enabled.
    return SystemLanguageModel.default.isAvailable
  }

  static func migrateMainMenuIcons(delegate: AppDelegate) {
    // [macOS 27] Fallback for systems without the renamed symbol
    let image = NSImage(systemSymbolName: Icons.interfaceWindowOnRectangle, accessibilityDescription: nil)
      ?? NSImage(systemSymbolName: "macwindow.on.rectangle", accessibilityDescription: nil)

    delegate.fileNewTabItem?.image = image
    delegate.fileReopenClosedTabItem?.image = image
    delegate.fileNewTabItem?.ensureImageVisibility()
    delegate.fileReopenClosedTabItem?.ensureImageVisibility()
  }

  static var reduceTransparency: Bool {
    AppPreferences.Window.reduceTransparency || NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency
  }

  static var reduceMotion: Bool {
    NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
  }

  /**
   Returns either an `NSGlassEffectView`, or an `NSVisualEffectView` as fallback.

   `NSGlassEffectView` is used when it is available and `modernStyle` is true.
   */
  static var modernEffectView: NSView.Type {
    guard #available(macOS 26.0, *), modernStyle && AppRuntimeConfig.visualEffectType == .glass else {
      return NSVisualEffectView.self
    }

    return NSGlassEffectView.self
  }
}

// MARK: - Private

private extension AppDesign {
  static var isMacOSTahoe: Bool {
    guard #available(macOS 26.0, *) else {
      return false
    }

    return true
  }
}
