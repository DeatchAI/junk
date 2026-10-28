//
//  AISettings.swift
//  lazzy
//
//  User-configurable AI settings persisted in UserDefaults
//

import SwiftUI

struct AISettings {

  // MARK: - Keys
  private enum Keys {
    static let defaultModel = "ai_default_model"
    static let temperature = "ai_temperature"
    static let maxSteps = "ai_max_steps"
    static let systemPrompt = "ai_system_prompt"
    static let zeroDataRetention = "ai_zero_data_retention"
  }

  // MARK: - Defaults
  static let defaultModelValue = "Codex"
  static let defaultTemperature: Double = 0.7
  static let defaultMaxSteps: Int = 30
  static let defaultSystemPrompt = ""
  private static let legacySystemPrompt =
    "You are Detach, a local AI assistant that helps with coding, macOS tasks, and browser work."

  static var additionalInstructions: String? {
    let value = systemPrompt.trimmingCharacters(in: .whitespacesAndNewlines)
    return value.isEmpty || value == legacySystemPrompt ? nil : value
  }

  static func retireDefaultPersona() {
    if systemPrompt == legacySystemPrompt { systemPrompt = "" }
  }
  static let defaultZeroDataRetention: Bool = true

  // MARK: - Properties with AppStorage persistence

  @AppStorage(Keys.defaultModel)
  static var defaultModel: String = defaultModelValue

  @AppStorage(Keys.temperature)
  static var temperature: Double = defaultTemperature

  @AppStorage(Keys.maxSteps)
  static var maxSteps: Int = defaultMaxSteps

  @AppStorage(Keys.systemPrompt)
  static var systemPrompt: String = defaultSystemPrompt


  @AppStorage(Keys.zeroDataRetention)
  static var zeroDataRetention: Bool = defaultZeroDataRetention

  // MARK: - Reset

  static func resetToDefaults() {
    defaultModel = defaultModelValue
    temperature = defaultTemperature
    maxSteps = defaultMaxSteps
    systemPrompt = defaultSystemPrompt
    zeroDataRetention = defaultZeroDataRetention
  }
}

struct DetachSettings {
  private enum Keys {
    static let selectedAgent = "detach_selected_agent"
    static let selectedModelPrefix = "detach_selected_model_"
    static let selectedModelSettingsPrefix = "detach_selected_model_settings_"
    static let permissionModePrefix = "detach_permission_mode_"
  }

  static let defaultAgent = "codex"
  static let permissionModeDidChange = Notification.Name("DetachPermissionModeDidChange")

  static func permissionMode(for agent: String) -> AgentPermissionMode {
    guard AgentPermissionMode.supportsOverrides(for: agent),
      let value = UserDefaults.standard.string(forKey: Keys.permissionModePrefix + agent)
    else { return .native }
    return AgentPermissionMode(rawValue: value) ?? .native
  }

  static func setPermissionMode(_ mode: AgentPermissionMode, for agent: String) {
    let key = Keys.permissionModePrefix + agent
    guard UserDefaults.standard.string(forKey: key) != mode.rawValue else { return }
    UserDefaults.standard.set(mode.rawValue, forKey: key)
    NotificationCenter.default.post(name: permissionModeDidChange, object: nil, userInfo: ["agent": agent])
  }

  static var selectedAgent: String {
    get {
      let saved = UserDefaults.standard.string(forKey: Keys.selectedAgent) ?? defaultAgent
      guard let provider = AgentProvider(rawValue: saved) else {
        UserDefaults.standard.set(defaultAgent, forKey: Keys.selectedAgent)
        return defaultAgent
      }
      return provider.id
    }
    set {
      UserDefaults.standard.set(AgentProvider(rawValue: newValue)?.id ?? defaultAgent, forKey: Keys.selectedAgent)
    }
  }

  static func selectedModel(for agent: String) -> String? {
    let value = UserDefaults.standard.string(forKey: Keys.selectedModelPrefix + agent)
    return value?.isEmpty == false ? value : nil
  }

  static func setSelectedModel(_ model: String?, for agent: String) {
    let key = Keys.selectedModelPrefix + agent
    if let model, !model.isEmpty {
      UserDefaults.standard.set(model, forKey: key)
    } else {
      UserDefaults.standard.removeObject(forKey: key)
    }
  }

  static func modelSettings(for agent: String, model: String?) -> AgentModelSettings? {
    guard let data = UserDefaults.standard.data(forKey: modelSettingsKey(agent: agent, model: model)) else {
      return nil
    }
    return try? JSONDecoder().decode(AgentModelSettings.self, from: data)
  }

  static func setModelSettings(_ settings: AgentModelSettings?, for agent: String, model: String?) {
    let key = modelSettingsKey(agent: agent, model: model)
    guard let settings, settings.reasoningEffort?.isEmpty == false,
          let data = try? JSONEncoder().encode(settings) else {
      UserDefaults.standard.removeObject(forKey: key)
      return
    }
    UserDefaults.standard.set(data, forKey: key)
  }

  private static func modelSettingsKey(agent: String, model: String?) -> String {
    let modelKey = model?.isEmpty == false ? model! : "__default__"
    return Keys.selectedModelSettingsPrefix + agent + "_" + modelKey
  }


}
