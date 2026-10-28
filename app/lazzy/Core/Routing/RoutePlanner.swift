import Foundation

enum RoutePlanner {
  static func shouldRoute(_ request: ChatRequest, configuration: RouterConfiguration) -> Bool {
    configuration.enabled && request.conversationId == nil && request.branchFrom == nil && request.actionId == nil
  }

  static func catalog(_ capabilities: [AgentCapability], configuration: RouterConfiguration,
    current: RouterPreset, usage: RouterUsageSnapshot = .unknown, now: Date = .now) -> [RouterCandidate] {
    let groups: [[RouterCandidate]] = capabilities.filter { $0.installed && AgentProvider(rawValue: $0.id) != nil }.map { agent in
      var options = agent.models.map { model in
        RouterCandidate(id: "", agent: agent.id, agentName: agent.displayName, model: model.id,
          modelName: model.displayName, efforts: model.reasoningEfforts ?? [], defaultEffort: model.defaultReasoningEffort)
      }
      // The provider's default is a valid choice even when discovery has no model list.
      options.insert(RouterCandidate(id: "", agent: agent.id, agentName: agent.displayName, model: nil,
        modelName: "Agent default", efforts: [], defaultEffort: nil), at: 0)
      return options.filter { !configuration.considerUsage || !usage.isReserved($0, reserve: configuration.reservePercent, now: now) }
    }
    let favorites = [current, configuration.fixedChoice] + configuration.activeRules.map(\.preset)
    let flat = groups.flatMap { $0 }
    var result = favorites.compactMap { preference in flat.first { $0.matches(preference) } }
    // Interleave providers so a large model catalog cannot crowd out other agents.
    for index in 0..<(groups.map(\.count).max() ?? 0) {
      for group in groups where group.indices.contains(index) { result.append(group[index]) }
    }
    var seen = Set<String>()
    return result.filter { seen.insert("\($0.agent)\u{0}\($0.model ?? "")").inserted }.prefix(255).enumerated().map { index, option in
      RouterCandidate(id: "route_\(index)", agent: option.agent, agentName: option.agentName,
        model: option.model, modelName: option.modelName, efforts: option.efforts, defaultEffort: option.defaultEffort)
    }
  }

  static func selection(_ classification: RouterClassification, candidates: [RouterCandidate], configuration: RouterConfiguration) throws -> RouterSelection {
    let threshold = max(0, min(1, configuration.minimumConfidence))
    guard [classification.confidence, classification.effortConfidence, classification.modelConfidence]
      .allSatisfy({ $0.isFinite && (0...1).contains($0) }),
      ["simple", "standard", "complex"].contains(classification.complexity)
    else { throw RouterError.unavailable("Jev returned an invalid routing classification.") }
    var unavailableRule: String?
    var uncertainRule: String?
    if let matches = classification.ruleMatches {
      let rules = configuration.activeRules
      guard matches.count == rules.count else { throw RouterError.unavailable("Preference matches are incomplete.") }
      for (rule, match) in zip(rules, matches) {
        guard match.confidence.isFinite, (0...1).contains(match.confidence) else {
          throw RouterError.unavailable("Jev returned an invalid preference match.")
        }
        // An uncertain higher-priority rule cannot safely be bypassed by a later one.
        if match.confidence < threshold { uncertainRule = rule.description; break }
        if !match.matches { continue }
        if let candidate = candidates.first(where: { $0.matches(rule.preset) }) {
          let preset = try validated(RouterPreset(agent: rule.preset.agent, model: rule.preset.model,
            effort: rule.preset.effort ?? inferredReasoning(for: candidate, classification: classification, configuration: configuration)), candidate: candidate)
          return RouterSelection(preset: preset, kind: classification.kind, confidence: match.confidence,
            reason: "Matched your preference: \(rule.description).", decisionModel: classification.decisionModel)
        }
        unavailableRule = rule.description
        break
      }
    } else {
      // Compatibility for older stored classifications and policy fixtures.
      guard classification.confidence >= threshold else {
        throw RouterError.unavailable("Jev could not confidently identify the task type.")
      }
      if let preference = configuration.preferences[classification.kind.rawValue], !preference.isAutomatic {
        if let candidate = candidates.first(where: { $0.matches(preference) }) {
          let preset = try validated(RouterPreset(agent: preference.agent, model: preference.model,
            effort: preference.effort ?? inferredReasoning(for: candidate, classification: classification, configuration: configuration)), candidate: candidate)
          return RouterSelection(preset: preset, kind: classification.kind, confidence: classification.confidence,
            reason: "Used your \(classification.kind.phrase) preference.", decisionModel: classification.decisionModel)
        }
        unavailableRule = classification.kind.phrase
      }
    }
    guard classification.modelConfidence >= threshold,
      let chosen = candidates.first(where: { $0.id == classification.candidateID })
    else { throw RouterError.unavailable((unavailableRule.map { "Your preference for \($0) was unavailable or within your usage reserve. " } ?? "") + "Jev could not confidently choose an available model.") }
    let effort = inferredReasoning(for: chosen, classification: classification, configuration: configuration)
    return RouterSelection(preset: RouterPreset(agent: chosen.agent, model: chosen.model, effort: effort),
      kind: classification.kind, confidence: classification.confidence,
      reason: (unavailableRule.map { "Your preference for \($0) was unavailable or within your usage reserve. " } ?? "")
        + (uncertainRule.map { "Could not confidently match your preference for \($0). " } ?? "")
        + "Chose from your available models using your \(configuration.priority.title.lowercased()) priority.",
      decisionModel: classification.decisionModel)
  }

  private static func inferredReasoning(for candidate: RouterCandidate, classification: RouterClassification,
    configuration: RouterConfiguration) -> String? {
    guard classification.effortConfidence >= max(0, min(1, configuration.minimumConfidence)) else { return nil }
    return reasoning(for: candidate, complexity: classification.complexity, priority: configuration.priority)
  }

  static func fixed(_ preset: RouterPreset, candidates: [RouterCandidate]) throws -> RouterSelection {
    guard let candidate = candidates.first(where: { $0.matches(preset) })
    else { throw RouterError.unavailable("Your fixed routing choice is unavailable or within your usage reserve.") }
    return RouterSelection(preset: try validated(preset, candidate: candidate), kind: nil, confidence: nil,
      reason: "Used the fixed choice in Auto router settings.", decisionModel: nil)
  }

  /// When discovery is unavailable, only forward the user's existing manual choice.
  /// This candidate is for fallback validation and must never be offered to Jev.
  static func manualFallbackCandidate(_ current: RouterPreset, configuration: RouterConfiguration, usage: RouterUsageSnapshot) -> RouterCandidate? {
    guard AgentProvider(rawValue: current.agent) != nil else { return nil }
    let candidate = RouterCandidate(id: "manual_fallback", agent: current.agent,
      agentName: AgentProvider.displayName(for: current.agent), model: current.model,
      modelName: current.model ?? "Agent default", efforts: current.effort.map { [$0] } ?? [], defaultEffort: current.effort)
    return configuration.considerUsage && usage.isReserved(candidate, reserve: configuration.reservePercent) ? nil : candidate
  }

  static func fallback(_ current: RouterPreset, candidates: [RouterCandidate], configuration: RouterConfiguration, reason: String) throws -> RouterSelection {
    guard configuration.fallback == .currentChoice, let candidate = candidates.first(where: { $0.matches(current) })
    else { throw RouterError.unavailable("Auto router could not start this task. Check Auto router in Settings.") }
    return RouterSelection(preset: try validated(current, candidate: candidate), kind: nil, confidence: nil,
      reason: "\(reason) Used your current agent and model, as configured in Settings.", decisionModel: nil)
  }

  private static func validated(_ preset: RouterPreset, candidate: RouterCandidate) throws -> RouterPreset {
    guard preset.effort == nil || candidate.efforts.contains(preset.effort!) else {
      throw RouterError.unavailable("The chosen model no longer supports the saved reasoning level.")
    }
    return preset
  }

  static func reasoning(for candidate: RouterCandidate, complexity: String, priority: RouterPriority) -> String? {
    guard !candidate.efforts.isEmpty else { return nil }
    let order: [String]
    if complexity == "complex" { order = priority == .quality ? ["xhigh", "high", "medium"] : ["high", "medium", "xhigh"] }
    else if complexity == "simple" || priority == .speed || priority == .allowance { order = ["low", "minimal", "medium"] }
    else { order = ["medium", "high", "low"] }
    return order.first(where: { candidate.efforts.contains($0) })
      ?? candidate.defaultEffort.flatMap { candidate.efforts.contains($0) ? $0 : nil }
  }

  /// Shared by live submission and Settings tests, including low-confidence and stop outcomes.
  static func evaluate(_ classification: RouterClassification?, candidates: [RouterCandidate], configuration: RouterConfiguration,
    current: RouterPreset, classificationFailure: String? = nil) -> RouterEvaluation {
    do {
      let choice: RouterSelection
      if !configuration.fixedChoice.isAutomatic {
        choice = try fixed(configuration.fixedChoice, candidates: candidates)
      } else if let classification {
        choice = try selection(classification, candidates: candidates, configuration: configuration)
      } else { throw RouterError.unavailable(classificationFailure ?? "No routing classification is available.") }
      return RouterEvaluation(classification: classification, selection: choice, usedFallback: false,
        summary: [classificationFailure, choice.reason].compactMap { $0 }.joined(separator: " "))
    } catch {
      let reason = error.localizedDescription
      if let choice = try? fallback(current, candidates: candidates, configuration: configuration, reason: reason) {
        return RouterEvaluation(classification: classification, selection: choice, usedFallback: true, summary: choice.reason)
      }
      return RouterEvaluation(classification: classification, selection: nil, usedFallback: false,
        summary: "\(reason) The configured routing policy would stop this task before starting an agent.")
    }
  }
}
