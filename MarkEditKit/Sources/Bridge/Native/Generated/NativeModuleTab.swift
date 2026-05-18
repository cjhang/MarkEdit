//
//  NativeModuleTab.swift
//
//  Generated using https://github.com/microsoft/ts-gyb
//
//  Don't modify this file manually, it's auto generated.
//
//  To make changes, edit template files under /CoreEditor/src/@codegen

import Foundation
import MarkEditCore

@MainActor
public protocol NativeModuleTab: NativeModule {
  func selectTab(index: Int)
}

public extension NativeModuleTab {
  var bridge: NativeBridge { NativeBridgeTab(self) }
}

@MainActor
final class NativeBridgeTab: NativeBridge {
  static let name = "tab"
  lazy var methods: [String: NativeMethod] = [
    "selectTab": { [weak self] in
      await self?.selectTab(parameters: $0)
    },
  ]

  private let module: NativeModuleTab
  private lazy var decoder = JSONDecoder()

  init(_ module: NativeModuleTab) {
    self.module = module
  }

  private func selectTab(parameters: Data) async -> Result<Any?, Error>? {
    struct Message: Decodable {
      var index: Int
    }

    let message: Message
    do {
      message = try decoder.decode(Message.self, from: parameters)
    } catch {
      Logger.assertFail("Failed to decode parameters: \(parameters)")
      return .failure(error)
    }

    module.selectTab(index: message.index)
    return .success(nil)
  }
}
