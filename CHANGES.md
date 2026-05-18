# Changes: "Go to Tab" Menu Items & Cmd+Number Tab Switching

## Summary
Added "Go to Tab 1" through "Go to Tab 6" menu items to the Window menu with Cmd+1–6 keyboard shortcuts. The previous Cmd+1–6 shortcuts (Heading 1–6 in Format > Headers) have been changed to Cmd+Ctrl+1–6. A new native bridge API `nativeModules.tab.selectTab({ index })` is exposed so extensions can programmatically switch tabs.

---

## Files Created

### 1. `CoreEditor/src/bridge/native/tab.ts`
```typescript
import { NativeModule } from '../nativeModule';

/**
 * @shouldExport true
 * @invokePath tab
 * @bridgeName NativeBridgeTab
 */
export interface NativeModuleTab extends NativeModule {
  selectTab({ index }: { index: CodeGen_Int }): void;
}
```

### 2. `MarkEditKit/Sources/Bridge/Native/Generated/NativeModuleTab.swift`
Swift bridge layer for the tab native module. Follows the same pattern as other generated `NativeModule*.swift` files.

### 3. `MarkEditKit/Sources/Bridge/Native/Modules/EditorModuleTab.swift`
Concrete `EditorModuleTab` class with delegate pattern (`EditorModuleTabDelegate`).
```swift
@MainActor
public protocol EditorModuleTabDelegate: AnyObject {
  func editorTabSelectTab(_ sender: EditorModuleTab, index: Int)
}

public final class EditorModuleTab: NativeModuleTab {
  private weak var delegate: EditorModuleTabDelegate?
  public init(delegate: EditorModuleTabDelegate) { self.delegate = delegate }
  public func selectTab(index: Int) { delegate?.editorTabSelectTab(self, index: index) }
}
```

---

## Files Modified

### 4. `CoreEditor/index.ts`
Two changes:
- Add import: `import { NativeModuleTab } from './src/bridge/native/tab';`
- Register in `window.nativeModules`: `tab: createNativeModule<NativeModuleTab>('tab'),`

### 5. `MarkEditMac/Base.lproj/Main.storyboard`
Add `<modifierMask key="keyEquivalentModifierMask" control="YES" command="YES"/>` to each Heading 1–6 menu item. Changes Cmd+1–6 → Cmd+Ctrl+1–6.

### 6. `MarkEditMac/Sources/Editor/Controllers/EditorViewController.swift`
Add `EditorModuleTab(delegate: self)` to the `NativeModules` array.

### 7. `MarkEditMac/Sources/Editor/Controllers/EditorViewController+Delegate.swift`
Add `EditorModuleTabDelegate` conformance:
```swift
// MARK: - EditorModuleTabDelegate

extension EditorViewController: EditorModuleTabDelegate {
  func editorTabSelectTab(_ sender: EditorModuleTab, index: Int) {
    guard let window = view.window, let tabGroup = window.tabGroup else { return }
    let windows = tabGroup.windows
    guard index > 0, index <= windows.count else { return }
    tabGroup.selectedWindow = windows[index - 1]
    windows[index - 1].makeKeyAndOrderFront(nil)
  }
}
```

### 8. `MarkEditMac/Sources/Main/Application/AppDelegate+Menu.swift`
Two changes:

**a)** Add `goToTab(_:)` action to AppDelegate (NOT EditorViewController — avoids fileprivate access control issue):
```swift
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
```

**b)** In `reconfigureMainWindowMenu(document:)`, add dynamic "Go to Tab" items:
```swift
// At the end of reconfigureMainWindowMenu, add:

let goToTabPrefix = "goToTab_"
let tabCount = NSApp.keyWindow?.tabGroup?.windows.count ?? 0

// Remove existing Go to Tab items
mainWindowMenu?.items
  .filter { $0.identifier?.rawValue.hasPrefix(goToTabPrefix) == true }
  .forEach { mainWindowMenu?.removeItem($0) }

let insertIndex = mainWindowMenu?.items.firstIndex {
  $0.action == #selector(NSWindow.performMiniaturize(_:))
} ?? 0

guard tabCount > 1, let menu = mainWindowMenu else { return }

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

if tabCount > 1 {
  let separator = NSMenuItem.separator()
  separator.identifier = NSUserInterfaceItemIdentifier("\(goToTabPrefix)separator")
  menu.insertItem(separator, at: insertIndex)
}
```

### 9. `MarkEditMac/Sources/Main/AppResources.swift`
Add to the `Localized` enum:
```swift
enum Window {
  static let goToTab = String(localized: "Go to Tab %d", comment: "Menu item to switch to a specific tab by number, e.g. 'Go to Tab 1'")
}
```

---

## Important: Avoid This Bug on Re-apply

**Do NOT** put `goToTab(_:)` inside a `private extension EditorViewController`. Swift's access control will prevent `#selector(EditorViewController.goToTab(_:))` from compiling in other files. Instead, put the method in a non-private extension of `AppDelegate` (in `AppDelegate+Menu.swift`) and target it as `NSApp.appDelegate` / `#selector(AppDelegate.goToTab(_:))`.

---

## Behavior

- "Go to Tab" items only appear when 2+ tabs are open, up to 6
- Menu items update dynamically each time the Window menu opens
- `window.nativeModules.tab.selectTab({ index: 1 })` exposed for extensions
- No existing APIs modified or removed

---

# Image Hover Preview

## Summary
Added an image preview tooltip that appears when hovering over markdown image syntax (`![alt](path)`). Local images are loaded via the existing `image-loader://` URL scheme; remote URLs pass through directly. Implemented entirely in JS/CSS — no native Swift changes.

---

## Files Created

### 1. `CoreEditor/src/modules/imagePreview/index.ts`
Tooltip module: document-level mouse event delegation, singleton tooltip element, URL resolution (local → `image-loader://`, remote → pass-through), debounced show (300ms) / hide (200ms), viewport-clamped positioning below or above the link, scroll dismissal, and theme-aware CSS variable injection from `globalState.colors`. See `changes.md` for full source.

### 2. `CoreEditor/src/modules/imagePreview/index.css`
Tooltip styles (fixed-position with max 400×300, CSS spinner for loading, reduced-motion support). Includes `.cm-md-imagePreview[hidden] { display: none }` to override the `display: flex` on the base class.

---

## Files Modified

### 3. `CoreEditor/src/styling/nodes/link.ts`
In the `standardMatcher.decorate` callback, detect image links by checking `window.editor.state.sliceDoc(from - 1, from) === '!'` and add `data-link-is-image: 'true'` to the decoration attributes.

### 4. `CoreEditor/index.html`
Added `<link>` for `./src/modules/imagePreview/index.css`.

### 5. `CoreEditor/index.ts`
Added `import { setUpImagePreview } from './src/modules/imagePreview'` and called `setUpImagePreview()` after `startObserving()`.

---

## Bugs to Avoid

1. **CSS `display: flex` overrides `[hidden]`**: The `.cm-md-imagePreview` class sets `display: flex`, which has the same specificity as the browser's `[hidden] { display: none }` UA rule. Since author stylesheets win, the `hidden` attribute becomes a no-op. Fix: add an explicit `.cm-md-imagePreview[hidden] { display: none }` rule.

2. **`mouseout` fires within the link**: `mouseout` bubbles from child text nodes when the cursor moves between them inside the same link element. The handler must check `enteringLink` (i.e., `relatedTarget` is still inside `.cm-md-link`) and keep the tooltip visible.

---

## Behavior

- Hover over `![alt](path)` — after 300ms, a tooltip appears showing the image
- Move mouse away — after 200ms, the tooltip hides
- Moving from link to tooltip keeps it visible
- Scrolling the editor dismisses the tooltip immediately
- Broken images show an error message
- Tooltip theme colors match the active editor theme
- No native Swift changes; no existing APIs modified
