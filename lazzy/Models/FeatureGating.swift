//
//  FeatureGating.swift
//  lazzy
//
//  Feature gating configuration mirroring server-side features.ts
//

import Foundation

/// Models available to free-tier, pro_byok, and lifetime users.
/// These are cost-effective models suitable for basic usage.
struct FeatureGating {

  static let freeTierModels: Set<String> = [
    // Google - Fast/cheap
    "Gemini 2.5 Flash",
    "Gemini 2.0 Flash",
    "Gemini 2.0 Flash Lite",
    "Gemini 2.5 Flash Lite",

    // OpenAI - Mini/Nano variants
    "GPT-4o Mini",
    "GPT-4.1 Mini",
    "GPT-4.1 Nano",
    "GPT-5 Mini",
    "GPT-5 Nano",
    "o3-mini",
    "o4-mini",

    // xAI - Mini variants
    "Grok 3 Mini",
    "Grok 3 Mini Fast",
    "Grok 4 Fast Non-Reasoning",
    "Grok 4 Fast Reasoning",

    // Mistral - Small/Mini variants
    "Mistral Small",
    "Ministral 3B",
    "Ministral 8B",
    "Devstral Small",

    // DeepSeek - All (very affordable)
    "DeepSeek R1",
    "DeepSeek V3",
    "DeepSeek V3.1",
    "DeepSeek V3.2",

    // Meta Llama - All (open source)
    "Llama 3.3 70B",
    "Llama 3.1 8B",
    "Llama 3.1 70B",
    "Llama 4 Maverick",
    "Llama 4 Scout",

    // Qwen - Affordable tiers
    "Qwen 3 14B",
    "Qwen 3 30B",
    "Qwen 3 32B",

    // Perplexity - Search-enhanced (affordable)
    "Sonar",
    "Sonar Reasoning",

    // Meta Llama - Smaller models
    "Llama 3.2 1B",
    "Llama 3.2 3B",

  ]

  static let premiumModels: Set<String> = [
    // Google - Pro tier
    "Gemini 2.5 Pro",
    "Gemini 3 Flash",
    "Gemini 3 Pro Preview",

    // OpenAI - Flagship models
    "GPT-4o",
    "GPT-4.1",
    "GPT-5",
    "GPT-5 Pro",
    "GPT-5.2",
    "o1",
    "o3",
    "o3 Pro",

    // Anthropic - All (premium pricing)
    "Claude 3.5 Sonnet",
    "Claude 3.5 Haiku",
    "Claude 3.7 Sonnet",
    "Claude Sonnet 4",
    "Claude Sonnet 4.5",
    "Claude Opus 4",
    "Claude Opus 4.1",
    "Claude Opus 4.5",
    "Claude Opus 4.6",
    "Claude Haiku 4.5",

    // xAI - Full versions
    "Grok 3",
    "Grok 3 Fast",
    "Grok 4",

    // Mistral - Large/Pro
    "Mistral Large 3",
    "Mistral Medium",
    "Magistral Medium",
    "Pixtral Large",
    "Codestral",

    // Moonshot Kimi
    "Kimi K2",
    "Kimi K2 Turbo",
    "Kimi K2 Thinking",
    "Kimi K2 Thinking Turbo",

    // Qwen - Premium tiers
    "Qwen 3 235B",
    "Qwen 3 Max",
    "Qwen 3 Coder",
    "Qwen 3 VL Instruct",

    // Perplexity - Premium search
    "Sonar Pro",
    "Sonar Reasoning Pro",

    // Meta Llama - Larger models
    "Llama 3.2 11B",
    "Llama 3.2 90B",
  ]

  /// Check if a model is available to free-tier users
  static func isFreeTierModel(_ modelName: String) -> Bool {
    if modelName.hasPrefix("ollama:") || modelName.hasPrefix("lmstudio:") {
      return true
    }
    return freeTierModels.contains(modelName)
  }

  /// Check if a model is premium (requires Pro or Business)
  static func isPremiumModel(_ modelName: String) -> Bool {
    premiumModels.contains(modelName)
  }

  /// Get all models with their availability status for a plan
  static func getAllModelsWithAvailability(for planType: SubscriptionPlanType) -> [(
    model: String, isAvailable: Bool
  )] {
    let allModels = Array(freeTierModels) + Array(premiumModels)
    return allModels.map { model in
      let isAvailable = planType.hasAllModels || freeTierModels.contains(model)
      return (model: model, isAvailable: isAvailable)
    }
  }
}
