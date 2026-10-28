import Foundation

enum RouterTaskKind: String, Codable, CaseIterable, Identifiable {
  case general, ui, debugging, review, planning, writing, research
  var id: String { rawValue }
  var phrase: String { self == .ui ? "UI and design" : title.lowercased() }
  var classificationCriteria: String {
    switch self {
    case .ui: return "Visual design and frontend presentation: layout, spacing, typography, styling, polish, landing pages and interfaces. Includes fixing an ugly or janky interface when the goal is visual improvement."
    case .debugging: return "Diagnose and repair functional defects, crashes, failing tests or incorrect behavior. Visual styling and layout polish belong to UI and design even if the user says fix."
    case .review: return "Review or audit existing code and changes for correctness, regressions or missing tests."
    case .planning: return "Plan implementation, choose architecture or reason about system design and tradeoffs."
    case .writing: return "Draft, rewrite, edit or summarize text and documentation."
    case .research: return "Find and compare information, investigate sources or answer research questions."
    case .general: return "Implement features or perform other work whose main goal is not covered by a more specific category."
    }
  }
  var title: String {
    switch self {
    case .general: return "General work"
    case .ui: return "UI and design"
    case .debugging: return "Debugging"
    case .review: return "Code review"
    case .planning: return "Planning and architecture"
    case .writing: return "Writing"
    case .research: return "Research"
    }
  }
}

enum RouterPriority: String, Codable, CaseIterable, Identifiable {
  case balanced, quality, speed, allowance
  var id: String { rawValue }
  var title: String {
    switch self {
    case .balanced: return "Balance results and speed"
    case .quality: return "Best results"
    case .speed: return "Fast responses"
    case .allowance: return "Conserve my allowance"
    }
  }
}

enum RouterFallback: String, Codable, CaseIterable, Identifiable {
  case currentChoice, stop
  var id: String { rawValue }
  var title: String { self == .currentChoice ? "Use my current agent and model" : "Stop before starting the task" }
}

struct RouterPreset: Codable, Equatable {
  var agent: String = ""
  var model: String? = nil
  var effort: String? = nil
  var isAutomatic: Bool { agent.isEmpty }
}

struct RouterRule: Codable, Equatable, Identifiable {
  var id = UUID()
  var description: String = ""
  var preset = RouterPreset()
  // Preserve the meaning of migrated task categories until the user edits them.
  var matchingDetails: String? = nil
}

struct RouterConfiguration: Codable, Equatable {
  static let maxRules = 20
  var enabled = false
  var priority = RouterPriority.balanced
  var considerUsage = false
  var reservePercent = 10
  var fallback = RouterFallback.currentChoice
  var fixedChoice = RouterPreset()
  var preferences: [String: RouterPreset] = [:]
  // nil identifies settings saved before custom rules were introduced.
  var rules: [RouterRule]? = nil
  var activeRules: [RouterRule] {
    if let rules { return rules }
    return RouterTaskKind.allCases.compactMap { kind in
      guard let preset = preferences[kind.rawValue], !preset.isAutomatic else { return nil }
      return RouterRule(description: kind.title, preset: preset, matchingDetails: kind.classificationCriteria)
    }
  }
  mutating func setRules(_ updated: [RouterRule]) {
    rules = updated
    preferences = [:]
  }
  var minimumConfidence = 0.65

  static let storageKey = "detach_auto_router_v1"
  static func load(from defaults: UserDefaults = .standard) -> Self {
    guard let data = defaults.data(forKey: storageKey), let value = try? JSONDecoder().decode(Self.self, from: data)
    else { return Self() }
    var migrated = value
    if migrated.rules == nil { migrated.setRules(migrated.activeRules) }
    return migrated
  }
  func save(to defaults: UserDefaults = .standard) {
    if let data = try? JSONEncoder().encode(self) { defaults.set(data, forKey: Self.storageKey) }
  }
}
