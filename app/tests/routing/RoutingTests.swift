import Foundation

@main struct RoutingTests {
  static var checks = 0
  static func check(_ condition: @autoclosure () -> Bool, _ message: String) {
    precondition(condition(), message); checks += 1
  }

  @MainActor static func main() async throws {
    let models = [AgentModelCapability(id: "test-model", displayName: "Test model", reasoningEfforts: ["low", "medium", "high"], defaultReasoningEffort: nil, reasoningLabel: nil)]
    let agents = [agent("codex", models: models), agent("claude", models: models), agent("grok", models: models, installed: false)]
    var config = RouterConfiguration()
    let current = RouterPreset(agent: "codex", model: "test-model", effort: "medium")
    let choices = RoutePlanner.catalog(agents, configuration: config, current: current)
    check(choices.count == 4 && !choices.contains { $0.agent == "grok" }, "Only installed agents are eligible")
    config.enabled = true
    let original = ChatRequest(text: "Build a new screen", files: [.init(path: "/private/secret.png", mimeType: "image/png")],
      workspacePath: "/private/project", attachmentContext: "private attachment contents", model: "test-model", agent: "codex")
    check(RoutePlanner.shouldRoute(original, configuration: config), "New conversations route")
    check(!RoutePlanner.shouldRoute(ChatRequest(text: "Continue", conversationId: "saved"), configuration: config), "Existing sessions never reroute")
    check(!RoutePlanner.shouldRoute(ChatRequest(text: "Edit", branchFrom: .init(messageId: "m", promptHash: "hash")), configuration: config), "Branches keep their provider")
    check(!RoutePlanner.shouldRoute(ChatRequest(text: "Workflow", actionId: "explicit"), configuration: config), "Explicit workflows keep their selection")
    let claude = choices.first { $0.agent == "claude" && $0.model == "test-model" }!
    let decision = RouterClassification(kind: .ui, complexity: "complex", candidateID: claude.id, confidence: 0.9, decisionModel: "jev-fixture")
    let selection = try RoutePlanner.selection(decision, candidates: choices, configuration: config)
    check(selection.preset.agent == "claude" && selection.preset.effort == "high", "Routing chooses a supported effort")
    config.preferences["ui"] = current
    check(tryValue { try RoutePlanner.selection(decision, candidates: choices, configuration: config).preset } == current, "User specialty preferences win")
    config.preferences = [:]
    let invalid = RouterClassification(kind: .ui, complexity: "complex", candidateID: "invented", confidence: 0.99, decisionModel: "test")
    check((try? RoutePlanner.selection(invalid, candidates: choices, configuration: config)) == nil, "Unknown candidate IDs fail closed")
    let uncertain = RouterClassification(kind: .ui, complexity: "complex", candidateID: claude.id, confidence: 0.2, decisionModel: "test")
    check((try? RoutePlanner.selection(uncertain, candidates: choices, configuration: config)) == nil, "Low confidence uses fallback")
    let preview = RoutePlanner.evaluate(decision, candidates: choices, configuration: config, current: current)
    check(preview.classification?.kind == .ui && preview.selection?.preset.agent == "claude" && !preview.usedFallback, "The test interface uses the live routing policy")
    let uncertainPreview = RoutePlanner.evaluate(uncertain, candidates: choices, configuration: config, current: current)
    check(uncertainPreview.classification?.confidence == 0.2 && uncertainPreview.usedFallback, "Tests retain classification when policy uses a fallback")
    let fallback = try RoutePlanner.fallback(current, candidates: choices, configuration: config, reason: "Offline.")
    check(fallback.preset == current, "Fallback preserves the complete current selection")
    config.fallback = .stop
    let stoppedPreview = RoutePlanner.evaluate(uncertain, candidates: choices, configuration: config, current: current)
    check(stoppedPreview.selection == nil && stoppedPreview.classification?.kind == .ui, "Stop outcomes still show classification details")
    check((try? RoutePlanner.fallback(current, candidates: choices, configuration: config, reason: "Offline")) == nil, "Stop never starts another agent")
    config.fallback = .currentChoice
    config.fixedChoice = current
    let fixedPreview = RoutePlanner.evaluate(decision, candidates: choices, configuration: config, current: current)
    check(fixedPreview.classification?.candidateID == claude.id && fixedPreview.selection?.preset == current, "A fixed override remains distinct from Jev classification")
    config.fixedChoice = RouterPreset()
    check((try? RoutePlanner.fixed(.init(agent: "codex", model: "test-model", effort: "invented"), candidates: choices)) == nil, "Unsupported efforts cannot escape validation")

    let now = Date()
    let limit = RouterUsageWindow(agent: "codex", bucket: "codex:primary", modelIDs: nil, usedPercent: 95, resetsAt: now.timeIntervalSince1970 + 600)
    let usage = RouterUsageSnapshot(checkedAt: now.timeIntervalSince1970, windows: [limit], notices: [])
    config.considerUsage = true
    let available = RoutePlanner.catalog(agents, configuration: config, current: current, usage: usage, now: now)
    check(available.allSatisfy { $0.agent == "claude" }, "Known low allowance excludes that provider")
    check(!usage.isReserved(choices[0], reserve: 10, now: now.addingTimeInterval(121)), "Stale quota is unknown")
    check(!usage.isReserved(choices[0], reserve: 10, now: now.addingTimeInterval(-1)), "Future timestamps are unknown")
    let unknownScope = RouterUsageSnapshot(checkedAt: now.timeIntervalSince1970,
      windows: [.init(agent: "codex", bucket: "special", modelIDs: [], usedPercent: 100, resetsAt: nil)], notices: [])
    check(!unknownScope.isReserved(choices[0], reserve: 10, now: now), "Unknown bucket mapping cannot block unrelated models")
    check(!RouterUsageSnapshot.unknown.isReserved(choices[0], reserve: 10), "Missing usage is never invented")
    check((try? RoutePlanner.fallback(current, candidates: available, configuration: config, reason: "Offline")) == nil, "Fallback cannot bypass the usage reserve")
    check(RoutePlanner.manualFallbackCandidate(current, configuration: config, usage: usage) == nil, "Unknown catalog fallback still respects known quotas")
    let manual = RoutePlanner.manualFallbackCandidate(current, configuration: config, usage: .unknown)!
    check(tryValue { try RoutePlanner.fallback(current, candidates: [manual], configuration: config, reason: "Discovery pending").preset } == current, "Unknown catalogs preserve the exact manual fallback without calling Jev")

    let many = (0..<400).map { AgentModelCapability(id: "model-\($0)", displayName: "Model \($0)", reasoningEfforts: nil, defaultReasoningEffort: nil, reasoningLabel: nil) }
    let bounded = RoutePlanner.catalog([agent("codex", models: many), agents[1]], configuration: config, current: current)
    check(bounded.count == 255 && bounded.contains { $0.agent == "claude" }, "Large catalogs remain bounded and include other providers")
    try await clientChecks(original, choices: choices, configuration: config)
    try preferenceConfidenceChecks()
    try dynamicRuleChecks()
    try await submissionChecks(original)
    try await testInterfaceChecks(preview)
    print("Auto router: \(checks) policy, privacy, transport and cancellation checks passed")
  }

  static func tryValue<T>(_ body: () throws -> T) -> T? { try? body() }

  static func preferenceConfidenceChecks() throws {
    let opus = AgentModelCapability(id: "opus", displayName: "Opus", reasoningEfforts: ["low", "medium", "high", "max"], defaultReasoningEffort: nil, reasoningLabel: nil)
    let gpt = AgentModelCapability(id: "gpt-6.1-sol", displayName: "GPT-6.1-Sol", reasoningEfforts: ["low", "medium", "high", "max"], defaultReasoningEffort: nil, reasoningLabel: nil)
    var configuration = RouterConfiguration()
    configuration.preferences["ui"] = RouterPreset(agent: "claude", model: "opus", effort: "high")
    let current = RouterPreset(agent: "codex", model: gpt.id, effort: "max")
    let candidates = RoutePlanner.catalog([agent("claude", models: [opus]), agent("codex", models: [gpt])], configuration: configuration, current: current)
    let codex = candidates.first { $0.agent == "codex" && $0.model == gpt.id }!
    let wire: [String: Any] = ["model": "jev-1.14.0", "answers": [
      "kind": ["type": "choice", "choice": "ui", "confidence": 0.98],
      "complexity": ["type": "choice", "choice": "complex", "confidence": 0.36],
      "route": ["type": "choice", "choice": codex.id, "confidence": 0.23],
    ]]
    var classification = try JevClient.classification(JSONSerialization.data(withJSONObject: wire))
    let result = RoutePlanner.evaluate(classification, candidates: candidates, configuration: configuration, current: current)
    check(result.selection?.preset == configuration.preferences["ui"] && !result.usedFallback,
      "UI → Claude Opus High wins even when model-ranking confidence is 23% and Jev proposes Codex")
    check(result.classification?.confidence == 0.98 && result.classification?.modelConfidence == 0.23,
      "Low model-ranking confidence is not presented as low task-classification confidence")
    configuration.preferences["ui"]?.effort = nil
    let uncertainEffort = try RoutePlanner.selection(classification, candidates: candidates, configuration: configuration)
    check(uncertainEffort.preset.agent == "claude" && uncertainEffort.preset.model == "opus" && uncertainEffort.preset.effort == nil,
      "Uncertain complexity preserves the preferred model and leaves automatic reasoning at the native default")
    configuration.preferences = [:]
    check(RoutePlanner.evaluate(classification, candidates: candidates, configuration: configuration, current: current).usedFallback,
      "Automatic model selection still uses fallback when ranking confidence is low and no preference exists")
    classification.routeConfidence = 0.95
    check(tryValue { try RoutePlanner.selection(classification, candidates: candidates, configuration: configuration).preset.effort } == .some(nil),
      "Uncertain complexity does not discard an otherwise confident model choice")
    configuration.preferences["ui"] = RouterPreset(agent: "claude", model: "opus", effort: "high")
    let codexOnly = candidates.filter { $0.agent == "codex" }
    let unavailable = try RoutePlanner.selection(classification, candidates: codexOnly, configuration: configuration)
    check(unavailable.preset.agent == "codex" && unavailable.reason.contains("unavailable"),
      "An ineligible saved preference is never executed and its replacement is explained")
    let uncertainTask = RouterClassification(kind: .ui, complexity: "complex", candidateID: codex.id, confidence: 0.23,
      decisionModel: "fixture", complexityConfidence: 0.9, routeConfidence: 0.95)
    check(RoutePlanner.evaluate(uncertainTask, candidates: candidates, configuration: configuration, current: current).usedFallback,
      "An uncertain task category cannot misapply a specialty preference")
  }

  static func dynamicRuleChecks() throws {
    let opus = AgentModelCapability(id: "opus", displayName: "Opus", reasoningEfforts: ["high"], defaultReasoningEffort: nil, reasoningLabel: nil)
    let gpt = AgentModelCapability(id: "gpt", displayName: "GPT", reasoningEfforts: ["high"], defaultReasoningEffort: nil, reasoningLabel: nil)
    var config = RouterConfiguration()
    config.preferences["ui"] = .init(agent: "claude", model: "opus", effort: "high")
    let suite = "detach.router.fixture.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suite)!
    defer { defaults.removePersistentDomain(forName: suite) }
    config.save(to: defaults)
    let migrated = RouterConfiguration.load(from: defaults)
    check(migrated.rules?.count == 1 && migrated.rules?.first?.preset == config.preferences["ui"] && migrated.preferences.isEmpty,
      "Old task preferences migrate to editable rules without losing their selected agent, model or effort")
    config.setRules([
      RouterRule(description: "Visual polish for landing pages", preset: .init(agent: "claude", model: "opus", effort: "high")),
      RouterRule(description: "Anything about a landing page", preset: .init(agent: "codex", model: "gpt", effort: "high"))
    ])
    let current = RouterPreset(agent: "codex", model: "gpt", effort: "high")
    let choices = RoutePlanner.catalog([agent("claude", models: [opus]), agent("codex", models: [gpt])], configuration: config, current: current)
    let codex = choices.first { $0.agent == "codex" && $0.model == "gpt" }!
    var classification = RouterClassification(kind: .general, complexity: "standard", candidateID: codex.id, confidence: 0.2,
      decisionModel: "fixture", complexityConfidence: 0.9, routeConfidence: 0.9,
      ruleMatches: [.init(matches: true, confidence: 0.95), .init(matches: true, confidence: 0.96)])
    let selected = try RoutePlanner.selection(classification, candidates: choices, configuration: config)
    check(selected.preset.agent == "claude" && selected.preset.model == "opus" && selected.reason.contains("Visual polish"),
      "First confident matching custom rule wins even when task-category confidence is low")
    config.rules?.swapAt(0, 1)
    check(tryValue { try RoutePlanner.selection(classification, candidates: choices, configuration: config).preset.agent } == "codex",
      "Changing rule order changes which overlapping preference wins")
    config.rules?.swapAt(0, 1)
    classification.ruleMatches = [.init(matches: false, confidence: 0.8), .init(matches: true, confidence: 0.9)]
    check(tryValue { try RoutePlanner.selection(classification, candidates: choices, configuration: config).preset.agent } == "codex",
      "A confident nonmatch allows a later rule")
    classification.ruleMatches = [.init(matches: true, confidence: 0.2), .init(matches: true, confidence: 0.9)]
    check(tryValue { try RoutePlanner.selection(classification, candidates: choices, configuration: config) .reason.contains("Could not confidently match") } == true,
      "An uncertain higher-priority rule does not silently activate a lower rule")
    classification.ruleMatches = [.init(matches: true, confidence: 0.95), .init(matches: false, confidence: 0.9)]
    let unavailable = try RoutePlanner.selection(classification, candidates: choices.filter { $0.agent == "codex" }, configuration: config)
    check(unavailable.preset.agent == "codex" && unavailable.reason.contains("unavailable"), "An unavailable preferred choice is explained")
    let request = try JevClient.request(prompt: "Polish the page", mimeTypes: [], candidates: choices, configuration: config, key: "key")
    let payload = try JSONSerialization.jsonObject(with: request.httpBody!) as! [String: Any]
    let questions = payload["questions"] as! [String: Any]
    let first = questions["rule_0"] as! [String: Any]
    check((first["criteria"] as! [String: String])["match"] == "Visual polish for landing pages" && questions["rule_1"] != nil,
      "Jev receives a separate semantic matching question for each user-defined rule")
    let wire: [String: Any] = ["model": "fixture", "answers": [
      "kind": ["type": "choice", "choice": "ui", "confidence": 0.2],
      "complexity": ["type": "choice", "choice": "standard", "confidence": 0.9],
      "route": ["type": "choice", "choice": codex.id, "confidence": 0.9],
      "rule_0": ["type": "choice", "choice": "match", "confidence": 0.96],
      "rule_1": ["type": "choice", "choice": "no_match", "confidence": 0.8]
    ]]
    let parsed = try JevClient.classification(JSONSerialization.data(withJSONObject: wire), rules: config.activeRules)
    check(parsed.ruleMatches?.first?.matches == true && parsed.ruleMatches?.last?.matches == false, "Rule matches are decoded independently")
    check((try? JevClient.classification(JSONSerialization.data(withJSONObject: wire), rules: config.activeRules + [RouterRule()])) == nil,
      "Incomplete rule answers fail safely")
    config.setRules([])
    check(config.activeRules.isEmpty && config.preferences.isEmpty, "Deleting migrated rules cannot restore old preferences")
  }

  static func agent(_ id: String, models: [AgentModelCapability], installed: Bool = true) -> AgentCapability {
    AgentCapability(id: id, displayName: id.capitalized, installed: installed, executablePath: nil, authHint: nil, models: models, defaultModel: nil)
  }

  static func clientChecks(_ original: ChatRequest, choices: [RouterCandidate], configuration: RouterConfiguration) async throws {
    let request = try JevClient.request(prompt: original.text, mimeTypes: ["image/png"], candidates: choices, configuration: configuration, key: "fixture-key")
    let body = String(data: request.httpBody!, encoding: .utf8)!
    check(!body.contains("fixture-key") && !body.contains("/private/") && !body.contains("attachment contents"), "Secrets, paths and attached contents are absent from routing context")
    check(request.value(forHTTPHeaderField: "Authorization") == "Bearer fixture-key", "Key is used only for authentication")
    check(request.url?.absoluteString == "https://api.typesafe.ai/v1/systemone" && request.timeoutInterval == 4, "Jev destination and timeout are fixed")
    let payload = try JSONSerialization.jsonObject(with: request.httpBody!) as! [String: Any]
    let state = payload["state"] as! [String: Any]
    check(state["request"] as? String == original.text && state["attachmentTypes"] as? [String] == ["image/png"], "Routing receives only the message and attachment types")
    let answers: [String: Any] = ["model": "jev-fixture", "answers": [
      "kind": ["type": "choice", "choice": "ui", "confidence": 0.95],
      "complexity": ["type": "choice", "choice": "standard", "confidence": 0.8],
      "route": ["type": "choice", "choice": choices[0].id, "confidence": 0.9],
    ]]
    RoutingURLProtocol.body = try JSONSerialization.data(withJSONObject: answers)
    let sessionConfig = URLSessionConfiguration.ephemeral
    sessionConfig.protocolClasses = [RoutingURLProtocol.self]
    let session = URLSession(configuration: sessionConfig)
    defer { session.invalidateAndCancel() }
    let client = JevClient(session: session)
    let result = try await client.classify(prompt: original.text, mimeTypes: [], candidates: choices, configuration: configuration, key: "fixture-key")
    check(result.confidence == 0.95 && result.effortConfidence == 0.8 && result.modelConfidence == 0.9
      && result.kind == .ui, "Task, complexity and model-choice confidence remain independent")
    check((try? JevClient.classification(Data("{}".utf8))) == nil, "Malformed answers fail closed")
    RoutingURLProtocol.status = 401
    RoutingURLProtocol.body = Data("private credential echoed by server".utf8)
    do {
      try await client.verify(key: "fixture-key")
      preconditionFailure("Authentication failure must throw")
    } catch { check(!error.localizedDescription.contains("private credential"), "API errors never expose response bodies") }
    RoutingURLProtocol.status = 200
  }

  @MainActor static func submissionChecks(_ request: ChatRequest) async throws {
    AutoRouter.shared.configuration.enabled = true
    let manager = WebSocketManager()
    var continuation: CheckedContinuation<RouterSelection, Error>?
    AutoRouter.shared.handler = { _ in try await withCheckedThrowingContinuation { continuation = $0 } }
    check(manager.beginAutoRouting(request), "Routing starts")
    check(!manager.beginAutoRouting(request), "Double Send cannot create a second routing call")
    while continuation == nil { await Task.yield() }
    check(manager.cancelAutoRouting(), "Stop cancels pending routing")
    continuation?.resume(returning: RouterSelection(preset: .init(agent: "claude", model: "test-model", effort: "high"), kind: .ui,
      confidence: 0.9, reason: "fixture", decisionModel: "test"))
    await Task.yield(); await Task.yield()
    check(manager.dispatched.isEmpty, "A late response after Stop cannot launch a task")
    AutoRouter.shared.handler = { _ in RouterSelection(preset: .init(agent: "claude", model: "test-model", effort: "high"),
      kind: .ui, confidence: 0.9, reason: "fixture", decisionModel: "test") }
    check(manager.beginAutoRouting(request), "A new request can follow cancellation")
    while manager.routingTask != nil { await Task.yield() }
    check(manager.dispatched.count == 1 && manager.dispatched[0].agent == "claude", "Only the chosen request dispatches")
    check(manager.dispatched[0].text == request.text && manager.dispatched[0].files == request.files
      && manager.dispatched[0].attachmentContext == request.attachmentContext, "Routing preserves the original task and attachments")
    check(manager.dispatched[0].permissionMode == "native", "Permission mode comes from the chosen provider's settings")
    check(manager.autoRoutedChoice?.effort == "high", "Follow-ups retain their routed choice")
  }

  @MainActor static func testInterfaceChecks(_ preview: RouterEvaluation) async throws {
    let state = RouterTestState()
    var calls = 0
    state.prompt = "  "
    state.run { _ in calls += 1; return preview }
    check(!state.isRunning && calls == 0, "Blank test prompts never call Jev")
    state.prompt = " Classify this sample "
    var continuation: CheckedContinuation<RouterEvaluation, Error>?
    state.run { prompt in
      check(prompt == "Classify this sample", "Test prompts are trimmed")
      calls += 1
      return try await withCheckedThrowingContinuation { continuation = $0 }
    }
    state.run { _ in calls += 1; return preview }
    while continuation == nil { await Task.yield() }
    check(calls == 1, "Repeated clicks cannot create duplicate test requests")
    state.cancel(clearResult: true)
    continuation?.resume(returning: preview)
    await Task.yield(); await Task.yield()
    check(!state.isRunning && state.result == nil, "Cancelled tests ignore late results")
    state.run { _ in preview }
    while state.isRunning { await Task.yield() }
    check(state.result?.classification?.kind == .ui, "Successful tests expose classification")
    state.cancel(clearResult: true)
    check(state.result == nil, "Test results can be cleared without a chat")
  }
}
