//
//  BYOKSettings.swift
//  lazzy
//
//  BYOK (Bring Your Own Key) settings for custom API keys
//

import SwiftUI

/// Supported AI providers for BYOK
enum AIProvider: String, CaseIterable, Identifiable {
  case openai = "OpenAI"
  case anthropic = "Anthropic"
  case google = "Google"
  case xai = "xAI"
  case mistral = "Mistral"
  case groq = "Groq"
  case ollama = "Ollama"
  case lmstudio = "LM Studio"

  var id: String { rawValue }

  /// Display name for the provider
  var displayName: String { rawValue }

  /// Environment variable name used by the server
  var envVarName: String {
    switch self {
    case .openai: return "OPENAI_API_KEY"
    case .anthropic: return "ANTHROPIC_API_KEY"
    case .google: return "GOOGLE_GENERATIVE_AI_API_KEY"
    case .xai: return "XAI_API_KEY"
    case .mistral: return "MISTRAL_API_KEY"
    case .groq: return "GROQ_API_KEY"
    case .ollama: return "OLLAMA_BASE_URL"
    case .lmstudio: return "LM_STUDIO_BASE_URL"
    }
  }

  /// UserDefaults key for storing the API key or Base URL
  var storageKey: String { "byok_\(rawValue.lowercased())_api_key" }

  /// UserDefaults key for storing the selected model (local providers only)
  var modelStorageKey: String { "byok_\(rawValue.lowercased())_model" }

  /// Placeholder text for the input field
  var placeholder: String {
    switch self {
    case .ollama: return "Enter Base URL (default: http://localhost:11434)"
    case .lmstudio: return "Enter Base URL (default: http://localhost:1234/v1)"
    default: return "Enter your \(displayName) API key"
    }
  }

  /// Available models for this provider
  /// For local providers, we return a dynamic list based on user configuration
  var models: [String] {
    switch self {
    case .openai:
      return [
        "GPT-4o", "GPT-4o Mini", "GPT-4.1", "GPT-4.1 Mini", "GPT-4.1 Nano",
        "GPT-5", "GPT-5 Mini", "GPT-5 Nano", "GPT-5 Pro", "GPT-5.2",
        "o1", "o3", "o3-mini", "o3 Pro", "o4-mini",
      ]
    case .anthropic:
      return [
        "Claude 3.5 Sonnet", "Claude 3.5 Haiku", "Claude 3.7 Sonnet",
        "Claude Sonnet 4", "Claude Sonnet 4.5",
        "Claude Opus 4", "Claude Opus 4.1", "Claude Opus 4.5",
        "Claude Haiku 4.5", "Claude Opus 4.6",
      ]
    case .google:
      return [
        "Gemini 2.5 Flash", "Gemini 2.5 Flash Lite", "Gemini 2.5 Pro",
        "Gemini 2.0 Flash", "Gemini 2.0 Flash Lite",
        "Gemini 3 Flash", "Gemini 3 Pro Preview",
      ]
    case .xai:
      return [
        "Grok 3", "Grok 3 Fast", "Grok 3 Mini", "Grok 3 Mini Fast",
        "Grok 4", "Grok 4 Fast Non-Reasoning", "Grok 4 Fast Reasoning",
        "Grok 4.1 Fast Non-Reasoning", "Grok 4.1 Fast Reasoning",
      ]
    case .mistral:
      return [
        "Mistral Large 3", "Mistral Medium", "Mistral Small",
        "Ministral 3B", "Ministral 8B", "Ministral 14B",
        "Pixtral Large", "Codestral", "Devstral Small",
        "Magistral Medium", "Magistral Small",
      ]
    case .groq:
      return [
        "Llama 3.3 70B", "Llama 3.1 8B", "Llama 3.1 70B",
        "Llama 4 Maverick", "Llama 4 Scout",
      ]
    case .ollama:
      // Return the configured model, or a placeholder if none
      let model = UserDefaults.standard.string(forKey: modelStorageKey) ?? "llama3"
      return !model.isEmpty ? ["ollama:\(model)"] : ["ollama:llama3"]
    case .lmstudio:
      // Return the configured model, or a placeholder if none
      let model = UserDefaults.standard.string(forKey: modelStorageKey) ?? "local-model"
      return !model.isEmpty ? ["lmstudio:\(model)"] : ["lmstudio:local-model"]
    }
  }

  /// Whether this provider is a local AI provider
  var isLocal: Bool {
    self == .ollama || self == .lmstudio
  }
}

/// Manager for BYOK API key storage
struct BYOKSettings {

  // MARK: - BYOK Enabled Toggle

  private static let enabledKey = "byok_enabled"

  /// Whether BYOK mode is enabled
  static var isEnabled: Bool {
    get { UserDefaults.standard.bool(forKey: enabledKey) }
    set { UserDefaults.standard.set(newValue, forKey: enabledKey) }
  }

  // MARK: - API Key Storage

  /// Get API key for a provider
  static func apiKey(for provider: AIProvider) -> String {
    UserDefaults.standard.string(forKey: provider.storageKey) ?? ""
  }

  /// Set API key for a provider
  static func setAPIKey(_ key: String, for provider: AIProvider) {
    if key.isEmpty {
      UserDefaults.standard.removeObject(forKey: provider.storageKey)
    } else {
      UserDefaults.standard.set(key, forKey: provider.storageKey)
    }
  }

  /// Get configured model for a local provider
  static func model(for provider: AIProvider) -> String {
    UserDefaults.standard.string(forKey: provider.modelStorageKey) ?? ""
  }

  /// Set configured model for a local provider
  static func setModel(_ model: String, for provider: AIProvider) {
    if model.isEmpty {
      UserDefaults.standard.removeObject(forKey: provider.modelStorageKey)
    } else {
      UserDefaults.standard.set(model, forKey: provider.modelStorageKey)
    }
  }

  /// Check if a provider has an API key configured
  static func isConfigured(_ provider: AIProvider) -> Bool {
    !apiKey(for: provider).isEmpty
  }

  /// Cloud providers (excluding local ones)
  static var cloudProviders: [AIProvider] {
    AIProvider.allCases.filter { !$0.isLocal }
  }

  /// Local providers
  static var localProviders: [AIProvider] {
    AIProvider.allCases.filter { $0.isLocal }
  }

  /// Get all configured API keys as a dictionary
  static func allConfiguredKeys() -> [String: String] {
    var keys: [String: String] = [:]
    for provider in AIProvider.allCases {
      let key = apiKey(for: provider)
      if !key.isEmpty {
        keys[provider.envVarName] = key
      }
    }
    return keys
  }

  /// Clear all stored API keys
  static func clearAllKeys() {
    for provider in AIProvider.allCases {
      UserDefaults.standard.removeObject(forKey: provider.storageKey)
    }
  }

  /// Get available models based on configured API keys
  /// When BYOK is enabled, only shows models for providers with keys
  /// When BYOK is disabled, shows all models (using hosted keys)
  static func availableModels() -> [String] {
    if !isEnabled {
      // BYOK disabled - show all models (hosted keys available)
      return AIProvider.allCases.flatMap { $0.models }
    }

    // BYOK enabled - only show models for configured providers
    var models: [String] = []
    for provider in AIProvider.allCases {
      if isConfigured(provider) {
        models.append(contentsOf: provider.models)
      }
    }

    // If no keys configured, show Google models as default
    return models.isEmpty ? AIProvider.google.models : models
  }

  /// Get the first available model (for auto-selection when provider changes)
  static func defaultAvailableModel() -> String {
    return availableModels().first ?? "Gemini 2.5 Flash"
  }

  /// Get all models with their availability status based on user's plan
  /// Premium models are marked as unavailable for free-tier users
  static func modelsWithAvailability(for planType: SubscriptionPlanType) -> [(
    model: String, isAvailable: Bool
  )] {
    let baseModels = availableModels()
    return baseModels.map { model in
      let isAvailable = planType.hasAllModels || FeatureGating.isFreeTierModel(model)
      return (model: model, isAvailable: isAvailable)
    }
  }

  /// Get the first available model for a user's plan
  static func defaultModel(for planType: SubscriptionPlanType) -> String {
    let modelsWithStatus = modelsWithAvailability(for: planType)
    return modelsWithStatus.first(where: { $0.isAvailable })?.model ?? "Gemini 2.5 Flash"
  }
}
