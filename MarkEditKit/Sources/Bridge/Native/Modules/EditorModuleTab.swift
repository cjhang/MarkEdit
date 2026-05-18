//
//  EditorModuleTab.swift
//
//  Manually written module to expose tab switching to JavaScript extensions.
//

import Foundation

@MainActor
public protocol EditorModuleTabDelegate: AnyObject {
  func editorTabSelectTab(_ sender: EditorModuleTab, index: Int)
}

public final class EditorModuleTab: NativeModuleTab {
  private weak var delegate: EditorModuleTabDelegate?

  public init(delegate: EditorModuleTabDelegate) {
    self.delegate = delegate
  }

  public func selectTab(index: Int) {
    delegate?.editorTabSelectTab(self, index: index)
  }
}
