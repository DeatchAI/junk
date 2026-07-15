import AppKit
import Carbon.HIToolbox
import Combine
import Foundation

/// Manages global keyboard shortcuts for the app
class HotkeyManager: ObservableObject {

  static let shared = HotkeyManager()

  @Published private(set) var isOptionKeyMonitorActive = false

  private var eventHandler: EventHandlerRef?
  private var flagsMonitor: Any?

  // Store registered hotkey references
  private var registeredHotkeys: [String: EventHotKeyRef] = [:]

  // Cache for currently registered shortcuts to avoid redundant updates
  private var currentShortcuts: [Action: KeyShortcut] = [:]

  // Track option key state for "tap" detection
  private var optionKeyDownTime: Date?
  private var wasOptionKeyAlone = true

  // Maximum duration for "tap" (quick press and release)
  private let maxTapDuration: TimeInterval = 0.3

  // Callbacks
  var onQuickActionsTriggered: (() -> Void)?
  var onFloatingChatTriggered: (() -> Void)?
  var onHistoryTriggered: (() -> Void)?
  var onOptionKeyTapped: (() -> Void)?  // ⌥ alone (for Finder quick actions)

  private init() {
    setupEventHandler()
    setupOptionKeyMonitor()
  }

  deinit {
    unregisterAllHotkeys()
    stopOptionKeyMonitor()
    if let eventHandler = eventHandler {
      RemoveEventHandler(eventHandler)
    }
  }

  // MARK: - Option Key Monitor (for Finder integration)

  private func setupOptionKeyMonitor() {
    flagsMonitor = NSEvent.addGlobalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
      self?.handleFlagsChanged(event)
    }

    isOptionKeyMonitorActive = true
  }

  private func stopOptionKeyMonitor() {
    if let monitor = flagsMonitor {
      NSEvent.removeMonitor(monitor)
      flagsMonitor = nil
    }
    isOptionKeyMonitorActive = false
  }

  private func handleFlagsChanged(_ event: NSEvent) {
    let flags = event.modifierFlags
    let isOptionPressed = flags.contains(.option)
    let hasOtherModifiers =
      flags.contains(.command) || flags.contains(.control) || flags.contains(.shift)

    if isOptionPressed && !hasOtherModifiers {
      if optionKeyDownTime == nil {
        optionKeyDownTime = Date()
        wasOptionKeyAlone = true
      }
    } else if !isOptionPressed && optionKeyDownTime != nil {
      let pressDuration = Date().timeIntervalSince(optionKeyDownTime!)

      if wasOptionKeyAlone && pressDuration < maxTapDuration {
        if isFinderFrontmost() {
          DispatchQueue.main.async { [weak self] in
            self?.onOptionKeyTapped?()
          }
        }
      }

      optionKeyDownTime = nil
      wasOptionKeyAlone = true
    } else if hasOtherModifiers {
      wasOptionKeyAlone = false
    }
  }

  private func isFinderFrontmost() -> Bool {
    guard let frontApp = NSWorkspace.shared.frontmostApplication else {
      return false
    }
    return frontApp.bundleIdentifier == "com.apple.finder"
  }

  // MARK: - Dynamic Hotkey Registration

  enum Action: String {
    case quickActions = "quickActions"
    case floatingChat = "floatingChat"
    case history = "history"

    var id: UInt32 {
      switch self {
      case .quickActions: return 1
      case .floatingChat: return 2
      case .history: return 3
      }
    }
  }

  func updateShortcut(for action: Action, shortcut: KeyShortcut) {
    // Only update if the shortcut has actually changed
    if let current = currentShortcuts[action], current == shortcut {
      return
    }

    unregisterHotkey(for: action)
    registerHotkey(
      for: action, keyCode: UInt32(shortcut.keyCode), modifiers: UInt32(shortcut.modifiers))

    currentShortcuts[action] = shortcut
  }

  private func registerHotkey(for action: Action, keyCode: UInt32, modifiers: UInt32) {
    var hotKeyRef: EventHotKeyRef?
    let hotKeyID = EventHotKeyID(signature: OSType(0x4C5A_5A59), id: action.id)  // "LZZY"

    let status = RegisterEventHotKey(
      keyCode,
      modifiers,
      hotKeyID,
      GetApplicationEventTarget(),
      0,
      &hotKeyRef
    )

    if status == noErr, let ref = hotKeyRef {
      registeredHotkeys[action.rawValue] = ref
      print("✅ Registered hotkey for \(action.rawValue)")
    } else {
      print("❌ Failed to register hotkey for \(action.rawValue): \(status)")
    }
  }

  private func unregisterHotkey(for action: Action) {
    if let ref = registeredHotkeys[action.rawValue] {
      UnregisterEventHotKey(ref)
      registeredHotkeys.removeValue(forKey: action.rawValue)
      print("🔌 Unregistered hotkey for \(action.rawValue)")
    }
  }

  private func unregisterAllHotkeys() {
    for action in registeredHotkeys.keys {
      if let ref = registeredHotkeys[action] {
        UnregisterEventHotKey(ref)
      }
    }
    registeredHotkeys.removeAll()
  }

  // MARK: - Carbon Event Handler

  private func setupEventHandler() {
    var eventType = EventTypeSpec(
      eventClass: OSType(kEventClassKeyboard),
      eventKind: UInt32(kEventHotKeyPressed)
    )

    let handlerBlock: EventHandlerUPP = { _, event, userData -> OSStatus in
      guard let userData = userData else { return OSStatus(eventNotHandledErr) }
      let manager = Unmanaged<HotkeyManager>.fromOpaque(userData).takeUnretainedValue()

      var hotKeyID = EventHotKeyID()
      GetEventParameter(
        event,
        EventParamName(kEventParamDirectObject),
        EventParamType(typeEventHotKeyID),
        nil,
        MemoryLayout<EventHotKeyID>.size,
        nil,
        &hotKeyID
      )

      DispatchQueue.main.async {
        switch hotKeyID.id {
        case Action.quickActions.id:
          manager.onQuickActionsTriggered?()
        case Action.floatingChat.id:
          manager.onFloatingChatTriggered?()
        case Action.history.id:
          manager.onHistoryTriggered?()
        default:
          break
        }
      }

      return noErr
    }

    let userData = Unmanaged.passUnretained(self).toOpaque()
    let status = InstallEventHandler(
      GetApplicationEventTarget(),
      handlerBlock,
      1,
      &eventType,
      userData,
      &eventHandler
    )

    if status != noErr {
      print("❌ Failed to install event handler: \(status)")
    }
  }
}
