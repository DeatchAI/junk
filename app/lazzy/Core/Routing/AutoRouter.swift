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

  func refreshUsage(endpoint: RuntimeEndpoint? = nil) async -> RouterUsageSnapshot {
    let endpoint = endpoint ?? .local
    // No probing unless the user explicitly enables usage-aware routing.
    guard configuration.considerUsage else { return usage }
    var components = URLComponents()
    components.scheme = "http"; components.host = endpoint.host; components.port = endpoint.port
    components.path = "/api/agent-usage"
    guard let url = components.url else { return .unknown }
    var request = URLRequest(url: url,
      cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 4)
    request.setValue(endpoint.authorizationHeaderValue, forHTTPHeaderField: "Authorization")
    do {
      let (data, response) = try await client.session.data(for: request)
      try Task.checkCancellation()
      guard (response as? HTTPURLResponse)?.statusCode == 200, data.count < 100_000 else { return .unknown }
      let snapshot = try JSONDecoder().decode(RouterUsageSnapshot.self, from: data)
      if endpoint.machineID == nil { usage = snapshot }
      return snapshot
    } catch { return .unknown }
  }

  func route(_ request: ChatRequest, capabilities: [AgentCapability],
             endpoint: RuntimeEndpoint? = nil) async throws -> RouterSelection {
    let endpoint = endpoint ?? .local
    let evaluation = try await evaluate(request, capabilities: capabilities,
      classifyFixedChoice: false, endpoint: endpoint)
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
    return try await evaluate(request, capabilities: capabilities,
      classifyFixedChoice: true, endpoint: .local)
  }

  private func evaluate(_ request: ChatRequest, capabilities: [AgentCapability],
                        classifyFixedChoice: Bool, endpoint: RuntimeEndpoint) async throws -> RouterEvaluation {
    try Task.checkCancellation()
    let configuration = configuration
    let current = RouterPreset(agent: request.agent ?? DetachSettings.selectedAgent, model: request.model, effort: request.modelSettings?.reasoningEffort)
    let routeUsage = configuration.considerUsage ? await refreshUsage(endpoint: endpoint) : usage
    try Task.checkCancellation()
    let capabilities = capabilities.isEmpty ? self.capabilities : capabilities
    var candidates = RoutePlanner.catalog(capabilities, configuration: configuration, current: current, usage: routeUsage)
    if capabilities.isEmpty, let manual = RoutePlanner.manualFallbackCandidate(current, configuration: configuration, usage: routeUsage) {
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
    return RoutePlanner.evaluate(classification, candidates: candidates, configuration: configuration,
      current: current, classificationFailure: failure)
  }

  func clearRecords() { records = [] }
  private func record(_ selection: RouterSelection) {
    records.insert(RouterDecisionRecord(selection: selection, summary: selection.reason), at: 0)
    records = Array(records.prefix(20))
  }
}
