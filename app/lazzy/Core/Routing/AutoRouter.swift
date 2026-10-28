import Combine
import Foundation

/// All external routing traffic originates here, never in a coding-agent process.
@MainActor final class AutoRouter: ObservableObject {
  static let shared = AutoRouter()
  @Published var configuration: RouterConfiguration { didSet { configuration.save() } }
  @Published private(set) var records: [RouterDecisionRecord] = []
  @Published private(set) var usage = RouterUsageSnapshot.unknown
  @Published private(set) var hasKey = false
  @Published private(set) var keyStatus: String?
  @Published private(set) var isVerifying = false
  @Published var capabilities: [AgentCapability] = []
  private let client = JevClient()

  private init() {
    configuration = .load()
    hasKey = (try? RouterKeychain.read()) != nil
  }

  func saveKey(_ key: String) {
    do { try RouterKeychain.save(key); hasKey = true; keyStatus = "API key saved in Keychain." }
    catch { keyStatus = error.localizedDescription }
  }

  func removeKey() {
    do { try RouterKeychain.remove(); hasKey = false; keyStatus = "API key removed." }
    catch { keyStatus = error.localizedDescription }
  }

  func verifyKey() async {
    guard !isVerifying else { return }
    isVerifying = true
    defer { isVerifying = false }
    do {
      guard let key = try RouterKeychain.read() else { throw RouterError.unavailable("Save your Jev API key first.") }
      try await client.verify(key: key)
      keyStatus = "Connected to Jev. No task was submitted."
    } catch { keyStatus = error.localizedDescription }
  }

  func refreshUsage() async {
    // No probing unless the user explicitly enables usage-aware routing.
    guard configuration.considerUsage else { return }
    var request = URLRequest(url: URL(string: "http://127.0.0.1:\(ServerConfig.port)/api/agent-usage")!,
      cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 4)
    request.setValue(ServerConfig.authorizationHeaderValue, forHTTPHeaderField: "Authorization")
    do {
      let (data, response) = try await client.session.data(for: request)
      try Task.checkCancellation()
      guard (response as? HTTPURLResponse)?.statusCode == 200, data.count < 100_000 else { return }
      usage = try JSONDecoder().decode(RouterUsageSnapshot.self, from: data)
    } catch { /* Unknown usage never becomes an invented quota. */ }
  }

  func route(_ request: ChatRequest, capabilities: [AgentCapability]) async throws -> RouterSelection {
    let evaluation = try await evaluate(request, capabilities: capabilities, classifyFixedChoice: false)
    guard let selection = evaluation.selection else {
      records.insert(RouterDecisionRecord(selection: nil, summary: evaluation.summary), at: 0)
      records = Array(records.prefix(20))
      throw RouterError.unavailable(evaluation.summary)
    }
    record(selection)
    return selection
  }

  /// A test explicitly authorizes classification even when Auto is off or a fixed choice is saved.
  /// It never dispatches a chat, creates a session or appends to live routing records.
  func test(_ prompt: String, capabilities: [AgentCapability]) async throws -> RouterEvaluation {
    let agent = DetachSettings.selectedAgent
    let model = DetachSettings.selectedModel(for: agent)
    let request = ChatRequest(text: prompt, model: model, agent: agent,
      modelSettings: DetachSettings.modelSettings(for: agent, model: model))
    return try await evaluate(request, capabilities: capabilities, classifyFixedChoice: true)
  }

  private func evaluate(_ request: ChatRequest, capabilities: [AgentCapability], classifyFixedChoice: Bool) async throws -> RouterEvaluation {
    try Task.checkCancellation()
    let configuration = configuration
    let current = RouterPreset(agent: request.agent ?? DetachSettings.selectedAgent, model: request.model, effort: request.modelSettings?.reasoningEffort)
    if configuration.considerUsage { await refreshUsage() }
    try Task.checkCancellation()
    let capabilities = capabilities.isEmpty ? self.capabilities : capabilities
    var candidates = RoutePlanner.catalog(capabilities, configuration: configuration, current: current, usage: usage)
    if capabilities.isEmpty, let manual = RoutePlanner.manualFallbackCandidate(current, configuration: configuration, usage: usage) {
      candidates = [manual]
    }
    var classification: RouterClassification?
    var failure: String?
    if capabilities.isEmpty { failure = "Model discovery is not ready." }
    else if configuration.fixedChoice.isAutomatic || classifyFixedChoice {
      do {
        guard let key = try RouterKeychain.read() else { throw RouterError.unavailable("No Jev API key is saved.") }
        classification = try await client.classify(prompt: request.text,
          mimeTypes: request.files?.map(\.mimeType) ?? [], candidates: candidates, configuration: configuration, key: key)
        try Task.checkCancellation()
      } catch {
        try Task.checkCancellation()
        failure = error.localizedDescription
      }
    }
    return RoutePlanner.evaluate(classification, candidates: candidates, configuration: configuration, current: current, classificationFailure: failure)
  }

  func clearRecords() { records = [] }
  private func record(_ selection: RouterSelection) {
    records.insert(RouterDecisionRecord(selection: selection, summary: selection.reason), at: 0)
    records = Array(records.prefix(20))
  }
}
