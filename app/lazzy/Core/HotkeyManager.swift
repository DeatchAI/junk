import AppKit
import Carbon.HIToolbox
import Combine
import Foundation

/// Manages global keyboard shortcuts for the app
class HotkeyManager: ObservableObject {

  static let shared = HotkeyManager()

  private var eventHandler: EventHandlerRef?

  // Store registered hotkey references
  private var registeredHotkeys: [String: EventHotKeyRef] = [:]

  // Cache for currently registered shortcuts to avoid redundant updates
  private var currentShortcuts: [Action: KeyShortcut] = [:]

  // Callbacks
  var onQuickActionsTriggered: (() -> Void)?
  var onFloatingChatTriggered: (() -> Void)?
  var onResumeLastChatTriggered: (() -> Void)?
  var onHistoryTriggered: (() -> Void)?

  private init() {
    setupEventHandler()
  }

  deinit {
    unregisterAllHotkeys()
    if let eventHandler = eventHandler {
      RemoveEventHandler(eventHandler)
    }
  }

  // MARK: - Dynamic Hotkey Registration

  enum Action: String {
    case quickActions = "quickActions"
    case floatingChat = "floatingChat"
    case resumeLastChat = "resumeLastChat"
    case history = "history"

    var id: UInt32 {
      switch self {
      case .quickActions: return 1
      case .floatingChat: return 2
      case .resumeLastChat: return 3
      case .history: return 4
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
        case Action.resumeLastChat.id:
          manager.onResumeLastChatTriggered?()
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
