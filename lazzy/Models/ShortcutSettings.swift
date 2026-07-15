//
//  ShortcutSettings.swift
//  lazzy
//
//  User-configurable keyboard shortcuts persisted in UserDefaults
//

import Carbon.HIToolbox
import SwiftUI

struct KeyShortcut: Equatable {
  var keyCode: Int
  var modifiers: Int  // Carbon modifiers

  var displayString: String {
    var str = ""
    if modifiers & shiftKey != 0 { str += "⇧" }
    if modifiers & controlKey != 0 { str += "⌃" }
    if modifiers & optionKey != 0 { str += "⌥" }
    if modifiers & cmdKey != 0 { str += "⌘" }

    str += keyName(for: keyCode)
    return str
  }

  private func keyName(for keyCode: Int) -> String {
    switch keyCode {
    case kVK_Space: return "Space"
    case kVK_Return: return "Enter"
    case kVK_ANSI_A: return "A"
    case kVK_ANSI_B: return "B"
    case kVK_ANSI_C: return "C"
    case kVK_ANSI_D: return "D"
    case kVK_ANSI_E: return "E"
    case kVK_ANSI_F: return "F"
    case kVK_ANSI_G: return "G"
    case kVK_ANSI_H: return "H"
    case kVK_ANSI_I: return "I"
    case kVK_ANSI_J: return "J"
    case kVK_ANSI_K: return "K"
    case kVK_ANSI_L: return "L"
    case kVK_ANSI_M: return "M"
    case kVK_ANSI_N: return "N"
    case kVK_ANSI_O: return "O"
    case kVK_ANSI_P: return "P"
    case kVK_ANSI_Q: return "Q"
    case kVK_ANSI_R: return "R"
    case kVK_ANSI_S: return "S"
    case kVK_ANSI_T: return "T"
    case kVK_ANSI_U: return "U"
    case kVK_ANSI_V: return "V"
    case kVK_ANSI_W: return "W"
    case kVK_ANSI_X: return "X"
    case kVK_ANSI_Y: return "Y"
    case kVK_ANSI_Z: return "Z"
    case kVK_ANSI_0: return "0"
    case kVK_ANSI_1: return "1"
    case kVK_ANSI_2: return "2"
    case kVK_ANSI_3: return "3"
    case kVK_ANSI_4: return "4"
    case kVK_ANSI_5: return "5"
    case kVK_ANSI_6: return "6"
    case kVK_ANSI_7: return "7"
    case kVK_ANSI_8: return "8"
    case kVK_ANSI_9: return "9"
    default: return "Code \(keyCode)"
    }
  }
}

struct ShortcutSettings {
  // MARK: - Keys
  private enum Keys {
    static let quickActionsCode = "shortcut_qa_code"
    static let quickActionsMods = "shortcut_qa_mods"
    static let floatingChatCode = "shortcut_fc_code"
    static let floatingChatMods = "shortcut_fc_mods"
    static let historyPanelCode = "shortcut_hp_code"
    static let historyPanelMods = "shortcut_hp_mods"
    static let chatSubmitCode = "shortcut_cs_code"
    static let chatSubmitMods = "shortcut_cs_mods"
    static let chatNewChatCode = "shortcut_nc_code"
    static let chatNewChatMods = "shortcut_nc_mods"
  }

  // MARK: - Defaults
  static let defaultQuickActions = KeyShortcut(keyCode: kVK_Space, modifiers: optionKey)
  static let defaultFloatingChat = KeyShortcut(keyCode: kVK_Space, modifiers: optionKey | shiftKey)
  static let defaultHistoryPanel = KeyShortcut(keyCode: kVK_ANSI_H, modifiers: optionKey)
  static let defaultChatSubmit = KeyShortcut(keyCode: kVK_Return, modifiers: 0)
  static let defaultChatNewChat = KeyShortcut(keyCode: kVK_Return, modifiers: optionKey)

  // MARK: - Computed Properties for Easy Access

  static var quickActions: KeyShortcut {
    get {
      KeyShortcut(
        keyCode: UserDefaults.standard.integer(forKey: Keys.quickActionsCode) == 0
          && UserDefaults.standard.object(forKey: Keys.quickActionsCode) == nil
          ? defaultQuickActions.keyCode
          : UserDefaults.standard.integer(forKey: Keys.quickActionsCode),
        modifiers: UserDefaults.standard.object(forKey: Keys.quickActionsMods) == nil
          ? defaultQuickActions.modifiers
          : UserDefaults.standard.integer(forKey: Keys.quickActionsMods))
    }
    set {
      UserDefaults.standard.set(newValue.keyCode, forKey: Keys.quickActionsCode)
      UserDefaults.standard.set(newValue.modifiers, forKey: Keys.quickActionsMods)
    }
  }

  static var floatingChat: KeyShortcut {
    get {
      KeyShortcut(
        keyCode: UserDefaults.standard.integer(forKey: Keys.floatingChatCode) == 0
          && UserDefaults.standard.object(forKey: Keys.floatingChatCode) == nil
          ? defaultFloatingChat.keyCode
          : UserDefaults.standard.integer(forKey: Keys.floatingChatCode),
        modifiers: UserDefaults.standard.object(forKey: Keys.floatingChatMods) == nil
          ? defaultFloatingChat.modifiers
          : UserDefaults.standard.integer(forKey: Keys.floatingChatMods))
    }
    set {
      UserDefaults.standard.set(newValue.keyCode, forKey: Keys.floatingChatCode)
      UserDefaults.standard.set(newValue.modifiers, forKey: Keys.floatingChatMods)
    }
  }

  static var historyPanel: KeyShortcut {
    get {
      KeyShortcut(
        keyCode: UserDefaults.standard.integer(forKey: Keys.historyPanelCode) == 0
          && UserDefaults.standard.object(forKey: Keys.historyPanelCode) == nil
          ? defaultHistoryPanel.keyCode
          : UserDefaults.standard.integer(forKey: Keys.historyPanelCode),
        modifiers: UserDefaults.standard.object(forKey: Keys.historyPanelMods) == nil
          ? defaultHistoryPanel.modifiers
          : UserDefaults.standard.integer(forKey: Keys.historyPanelMods))
    }
    set {
      UserDefaults.standard.set(newValue.keyCode, forKey: Keys.historyPanelCode)
      UserDefaults.standard.set(newValue.modifiers, forKey: Keys.historyPanelMods)
    }
  }

  static var chatSubmit: KeyShortcut {
    get {
      KeyShortcut(
        keyCode: UserDefaults.standard.integer(forKey: Keys.chatSubmitCode) == 0
          && UserDefaults.standard.object(forKey: Keys.chatSubmitCode) == nil
          ? defaultChatSubmit.keyCode : UserDefaults.standard.integer(forKey: Keys.chatSubmitCode),
        modifiers: UserDefaults.standard.object(forKey: Keys.chatSubmitMods) == nil
          ? defaultChatSubmit.modifiers : UserDefaults.standard.integer(forKey: Keys.chatSubmitMods)
      )
    }
    set {
      UserDefaults.standard.set(newValue.keyCode, forKey: Keys.chatSubmitCode)
      UserDefaults.standard.set(newValue.modifiers, forKey: Keys.chatSubmitMods)
    }
  }

  static var chatNewChat: KeyShortcut {
    get {
      KeyShortcut(
        keyCode: UserDefaults.standard.integer(forKey: Keys.chatNewChatCode) == 0
          && UserDefaults.standard.object(forKey: Keys.chatNewChatCode) == nil
          ? defaultChatNewChat.keyCode
          : UserDefaults.standard.integer(forKey: Keys.chatNewChatCode),
        modifiers: UserDefaults.standard.object(forKey: Keys.chatNewChatMods) == nil
          ? defaultChatNewChat.modifiers
          : UserDefaults.standard.integer(forKey: Keys.chatNewChatMods))
    }
    set {
      UserDefaults.standard.set(newValue.keyCode, forKey: Keys.chatNewChatCode)
      UserDefaults.standard.set(newValue.modifiers, forKey: Keys.chatNewChatMods)
    }
  }

  // MARK: - Reset
  static func resetToDefaults() {
    quickActions = defaultQuickActions
    floatingChat = defaultFloatingChat
    historyPanel = defaultHistoryPanel
    chatSubmit = defaultChatSubmit
    chatNewChat = defaultChatNewChat
  }
}
