# Swift + SwiftUI (macOS) Agent Steering

This is the **pure Swift** steering set for MontE — a native macOS developer tool built with Swift Package Manager and SwiftUI.

## Architecture & Code Standards

1. **Swift 6 language mode, strict concurrency.** UI-bound types are `@MainActor`; cross-isolation values are `Sendable`; shared mutable state lives in an `actor` or is protected by locks.
2. **Clean architecture, strict call chain:** `View → ViewModel → Service → System API / Process`.
3. **MVVM with unidirectional flow:** `@Observable` view model exposing observable properties with dedicated action methods.
4. **macOS Integration:** App lifecycle is managed by an `AppDelegate` via `@NSApplicationDelegateAdaptor`. Menu-bar status items use `NSStatusItem` and `NSMenu` for dynamic menus and popovers. `LSUIElement = YES` in `Info.plist` keeps the app as an agent accessory.
5. **Safe Process Execution:** Subprocess execution (e.g. system commands) must use Foundation `Process` and `Pipe` with explicit argument arrays — never `system()` or string-concatenated commands.
6. **Pre-commit exposure check:** Scan for any hardcoded secrets, API keys, credentials, or personal machine paths (`/Users/...`) prior to committing.
