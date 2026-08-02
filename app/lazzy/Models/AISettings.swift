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
    static let imageModel = "ai_image_model"
    static let zeroDataRetention = "ai_zero_data_retention"
  }

  // MARK: - Defaults
  static let defaultModelValue = "Codex"
  static let defaultTemperature: Double = 0.7
  static let defaultMaxSteps: Int = 30
  static let defaultImageModelValue = "DALL-E 3"
  static let defaultSystemPrompt =
    "You are Detach, a local AI assistant that helps with coding, macOS tasks, and browser work."
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

  @AppStorage(Keys.imageModel)
  static var imageModel: String = defaultImageModelValue

  @AppStorage(Keys.zeroDataRetention)
  static var zeroDataRetention: Bool = defaultZeroDataRetention

  // MARK: - Reset

  static func resetToDefaults() {
    defaultModel = defaultModelValue
    temperature = defaultTemperature
    maxSteps = defaultMaxSteps
    systemPrompt = defaultSystemPrompt
    imageModel = defaultImageModelValue
    zeroDataRetention = defaultZeroDataRetention
  }
}

struct DetachSettings {
  private enum Keys {
    static let selectedAgent = "detach_selected_agent"
    static let selectedModelPrefix = "detach_selected_model_"
    static let migratedHostedOpenCodeSelection = "detach_migrated_hosted_opencode_selection_v1"
  }

  static let defaultAgent = "codex"

  @AppStorage(Keys.selectedAgent)
  static var selectedAgent: String = defaultAgent

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

  /// Until Hosted AI was split out, its persisted agent identifier was
  /// `opencode`. Preserve that existing choice once, then leave future
  /// standalone OpenCode selections untouched.
  static func migrateLegacyHostedOpenCodeSelection(availableAgentIDs: Set<String>) {
    guard !UserDefaults.standard.bool(forKey: Keys.migratedHostedOpenCodeSelection) else { return }
    defer { UserDefaults.standard.set(true, forKey: Keys.migratedHostedOpenCodeSelection) }

    guard selectedAgent == "opencode", availableAgentIDs.contains("hosted") else { return }
    if let selectedModel = selectedModel(for: "opencode") {
      setSelectedModel(selectedModel, for: "hosted")
      setSelectedModel(nil, for: "opencode")
    }
    selectedAgent = "hosted"
  }
}
