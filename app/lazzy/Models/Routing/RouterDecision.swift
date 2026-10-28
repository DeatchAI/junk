import Foundation

struct RouterCandidate: Equatable {
  let id: String
  let agent: String
  let agentName: String
  let model: String?
  let modelName: String
  let efforts: [String]
  let defaultEffort: String?

  var title: String { "\(agentName) · \(modelName)" }
  func matches(_ preset: RouterPreset) -> Bool { agent == preset.agent && model == preset.model }
}

struct RouterUsageWindow: Codable, Equatable {
  let agent: String
  let bucket: String
  /// nil means provider-wide; an empty array means the bucket's model mapping is unknown.
  let modelIDs: [String]?
  let usedPercent: Double
  let resetsAt: Double?
}

struct RouterUsageSnapshot: Codable, Equatable {
  let checkedAt: Double
  let windows: [RouterUsageWindow]
  let notices: [String]

  static let unknown = Self(checkedAt: 0, windows: [], notices: [])
  func isReserved(_ candidate: RouterCandidate, reserve: Int, now: Date = .now) -> Bool {
    guard now.timeIntervalSince1970 >= checkedAt, now.timeIntervalSince1970 - checkedAt < 120 else { return false }
    return windows.contains { window in
      guard window.agent == candidate.agent, window.usedPercent.isFinite,
        window.resetsAt.map({ $0 > now.timeIntervalSince1970 }) ?? true else { return false }
      if let models = window.modelIDs, !models.contains(candidate.model ?? "") { return false }
      return window.usedPercent >= 100 || 100 - window.usedPercent <= Double(max(0, min(95, reserve)))
    }
  }
}

struct RouterRuleMatch {
  let matches: Bool
  let confidence: Double
}

struct RouterClassification {
  let kind: RouterTaskKind
  let complexity: String
  let candidateID: String
  /// Confidence in the task category, independent of model-ranking uncertainty.
  let confidence: Double
  let decisionModel: String
  var complexityConfidence: Double? = nil
  var routeConfidence: Double? = nil
  var ruleMatches: [RouterRuleMatch]? = nil

  var effortConfidence: Double { complexityConfidence ?? confidence }
  var modelConfidence: Double { routeConfidence ?? confidence }
}

struct RouterSelection {
  let preset: RouterPreset
  let kind: RouterTaskKind?
  let confidence: Double?
  let reason: String
  let decisionModel: String?
}

struct RouterEvaluation {
  let classification: RouterClassification?
  let selection: RouterSelection?
  let usedFallback: Bool
  let summary: String
}

struct RouterDecisionRecord: Identifiable {
  let id = UUID()
  let date = Date()
  let selection: RouterSelection?
  let summary: String
}

enum RouterError: LocalizedError {
  case unavailable(String)
  var errorDescription: String? {
    switch self { case .unavailable(let message): return message }
  }
}
