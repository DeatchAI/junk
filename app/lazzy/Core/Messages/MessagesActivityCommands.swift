import Foundation

@MainActor
final class MessagesActivityCommands {
  private weak var store: DetachedRunStore?
  private weak var controls: DetachedRunControls?
  private let questions: AgentQuestionCenter
  private let send: (String) -> Void
  let choices = MessagesDecisionChoices()
  var approvalResponse: ((String, Bool) -> Bool)?

  func resetChoices() { choices.reset() }

  func questionIdentity(for run: DetachedAgentRun) -> String? {
    questions.requests.first { $0.runId == run.id }?.id
  }

  init(store: DetachedRunStore, controls: DetachedRunControls,
    questions: AgentQuestionCenter? = nil, send: @escaping (String) -> Void) {
    self.store = store
    self.controls = controls
    self.questions = questions ?? .shared
    self.send = send
  }

  private var runs: [DetachedAgentRun] {
    store?.runs.filter { !$0.isDebugPreview }.sorted { $0.updatedAt > $1.updatedAt } ?? []
  }

  func handle(_ text: String) {
    let parts = text.split(whereSeparator: \.isWhitespace)
    guard let command = parts.first?.lowercased() else { return }
    let args = Array(parts.dropFirst())
    switch command {
    case "status", "tasks":
      send(status())
    case "stop", "resume":
      let candidates = runs.filter { command == "stop" ? controls?.canStop($0) == true : controls?.canResume($0) == true }
      guard let run = target(args.first.map(String.init), in: candidates) else { return }
      if command == "stop" { controls?.stop(run) }
      else { controls?.resume(run) }
      send("\(command == "stop" ? "Stop" : "Continue") requested for #\(MessagesActivityRelay.shortID(run)).")
    case "choose":
      guard args.count == 2, let number = Int(args[1]) else {
        send("Use choose <choice-code> <number> from the question message.")
        return
      }
      choose(String(args[0]), number: number)
    case "approve", "deny":
      guard args.count == 1 else { send("Include the approval code shown in the request."); return }
      choose(String(args[0]), number: command == "approve" ? 1 : 2, approvalOnly: true)
    case "reply", "answer":
      guard let id = args.first, args.count >= (command == "answer" ? 3 : 2) else {
        send("Use reply <task-id> <message>, or answer <task-id> <question-number> <answer>.")
        return
      }
      guard let run = target(String(id), in: runs) else { return }
      if command == "answer" {
        guard let index = Int(args[1]) else { send("Use a question number, such as answer \(id) 1 <answer>."); return }
        answer(run, questionNumber: index, text: args.dropFirst(2).joined(separator: " "))
      } else if run.state == .awaitingInput {
        answer(run, questionNumber: nil, text: args.dropFirst().joined(separator: " "))
      } else {
        guard controls?.reply(to: run, text: args.dropFirst().joined(separator: " ")) == true else {
          send("That task cannot accept a follow-up yet. If it is no longer attached, reopen its conversation on your Mac.")
          return
        }
      }
    case "start":
      send("Start a task in Detach on your Mac. Results and decisions from every project appear here automatically; use reply <task-id> <message> to continue one.")
    default:
      send("Commands: status, stop <task-id>, resume <task-id>, reply <task-id> <message>, answer <task-id> <question-number> <answer>, choose <choice-code> <number>, approve <approval-code>, deny <approval-code>. Start tasks on your Mac; all projects are included.")
    }
  }

  func status() -> String {
    guard !runs.isEmpty else { return "No live activities yet. Start a task in Detach on your Mac; results and decisions from every project will appear here." }
    return runs.prefix(10).map { run in
      let short = MessagesActivityRelay.shortID(run)
      let ambiguous = runs.filter { MessagesActivityRelay.shortID($0) == short }.count > 1
      let identifier = ambiguous ? "\nFull ID: \(MessagesActivityRelay.normalize(run.id))" : ""
      return "\(MessagesActivityRelay.heading(run))\(identifier)\n\(MessagesNotificationText.title(run.taskTitle)) — \(run.stateLabel)"
    }.joined(separator: "\n\n")
  }

  private func target(_ token: String?, in candidates: [DetachedAgentRun]) -> DetachedAgentRun? {
    if let token {
      let key = MessagesActivityRelay.normalize(token)
      let matches = candidates.filter { key.count >= 6 && MessagesActivityRelay.normalize($0.id).hasPrefix(key) }
      if matches.count == 1 { return matches[0] }
      send(matches.isEmpty ? "Task not found or unavailable. Send status for current task IDs."
        : "That ID matches multiple tasks. Send status for the full task IDs.")
    } else if candidates.count == 1 {
      return candidates[0]
    } else {
      send("Include a task ID, such as stop <task-id>. Send status to see your tasks.")
    }
    return nil
  }

  func questionText(for run: DetachedAgentRun, excluding: Set<String> = []) -> String? {
    guard let request = questions.requests.first(where: { $0.runId == run.id }) else { return nil }
    if request.questions.contains(where: { $0.isSecret == true }) {
      return "This task needs private input. Answer on your Mac."
    }
    return request.questions.enumerated().filter { !excluding.contains($0.element.id) }.map { index, question in
      var lines = ["\(index + 1). \(question.question)"]
      if let options = question.options, !options.isEmpty {
        let code = choices.code(for: .question(runID: run.id, requestID: request.id, questionID: question.id))
        lines.append(contentsOf: options.enumerated().map { "\($0.offset + 1). \($0.element.label)" })
        lines.append("Choose: choose \(code) <number>")
      }
      lines.append(request.questions.count == 1
        ? "Or reply \(MessagesActivityRelay.shortID(run)) <answer>"
        : "Or answer \(MessagesActivityRelay.shortID(run)) \(index + 1) <answer>")
      return lines.joined(separator: "\n")
    }.joined(separator: "\n\n")
  }

  func approvalText(for run: DetachedAgentRun) -> String? {
    guard let approval = run.approval else { return nil }
    let detail = [approval.description, approval.command].filter { !$0.isEmpty }.joined(separator: "\n")
    guard approvalResponse != nil, detail.count <= 1_200 else {
      return "\(String(MessagesPollDecision.line(approval.description).prefix(240)))\nReview the full action on your Mac."
    }
    let code = choices.code(for: .approval(runID: run.id, requestID: approval.id))
    return "\(detail)\nApprove once: approve \(code)\nDeny: deny \(code)\nAvailable while the request is pending."
  }

  @discardableResult
  func choose(_ code: String, number: Int, approvalOnly: Bool = false) -> Bool {
    guard let choice = choices.choice(for: code) else {
      send("That choice has expired or is no longer available. Use the latest request.")
      return false
    }
    switch choice {
    case .approval(let runID, let requestID):
      guard number == 1 || number == 2,
        let run = runs.first(where: { $0.id == runID }),
        run.state == .awaitingApproval, run.approval?.id == requestID else {
        send("That approval is no longer waiting, or the choice is invalid.")
        return false
      }
      guard approvalResponse?(requestID, number == 1) == true else {
        send("That approval is no longer available. Check Detach on your Mac.")
        return false
      }
      choices.remove(code)
      send("Decision sent for #\(MessagesActivityRelay.shortID(run)).")
      return true
    case .question(let runID, let requestID, let questionID):
      guard !approvalOnly,
        let run = runs.first(where: { $0.id == runID }), run.state == .awaitingInput,
        let request = questions.requests.first(where: { $0.id == requestID && $0.runId == runID }),
        let index = request.questions.firstIndex(where: { $0.id == questionID }),
        let options = request.questions[index].options, options.indices.contains(number - 1) else {
        send("That question or choice is no longer available. Use the latest request.")
        return false
      }
      guard answer(run, questionNumber: index + 1, text: options[number - 1].label) else { return false }
      choices.remove(code)
      return true
    }
  }

  @discardableResult
  private func answer(_ run: DetachedAgentRun, questionNumber: Int?, text: String) -> Bool {
    guard let request = questions.requests.first(where: { $0.runId == run.id }),
      !questions.submitting.contains(request.id) else { send("That question is no longer waiting for an answer."); return false }
    guard !request.questions.contains(where: { $0.isSecret == true }) else {
      send("Answer private questions on your Mac.")
      return false
    }
    let index = (questionNumber ?? 1) - 1
    guard (questionNumber != nil || request.questions.count == 1),
      request.questions.indices.contains(index) else {
      send("Choose a question number: answer \(MessagesActivityRelay.shortID(run)) 1 <answer>.")
      return false
    }
    questions.setAnswer(text, questionID: request.questions[index].id, requestID: request.id)
    let remaining = request.questions.filter { questions.answer(for: $0, in: request).trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }.count
    if remaining == 0 { questions.submit(request); send("Answer sent to #\(MessagesActivityRelay.shortID(run)).") }
    else { send("Answer saved. \(remaining) question(s) still need an answer.") }
    return true
  }
  func isPending(_ decision: MessagesPollDecision) -> Bool {
    guard case .native(let code, let choice) = decision.target,
      choices.choice(for: code) == choice,
      decision.requestFingerprint == requestFingerprint(for: choice) else { return false }
    switch choice {
    case .approval(let runID, let requestID):
      return approvalResponse != nil && runs.contains {
        $0.id == runID && $0.state == .awaitingApproval && $0.approval?.id == requestID
      }
    case .question(let runID, let requestID, let questionID):
      return runs.contains { $0.id == runID && $0.state == .awaitingInput } &&
        questions.requests.contains {
          $0.id == requestID && $0.runId == runID && !questions.submitting.contains($0.id) &&
            !$0.questions.contains { $0.isSecret == true } && $0.questions.contains { $0.id == questionID }
        }
    }
  }

  func polls(for run: DetachedAgentRun) -> [MessagesPollDecision] {
    let heading = MessagesActivityRelay.heading(run)
    if run.state == .awaitingApproval, let approval = run.approval, approvalResponse != nil {
      let choice = MessagesDecisionChoices.Choice.approval(runID: run.id, requestID: approval.id)
      let code = choices.code(for: choice)
      let decision = MessagesPollDecision.make(target: .native(code: code, choice: choice), heading: heading,
        question: approval.description.isEmpty ? "Approve this action once?" : approval.description,
        options: ["Approve once", "Deny"], detail: approval.command, lifetime: 60,
        requestFingerprint: requestFingerprint(for: choice))
      return decision.map { [$0] } ?? []
    }
    guard run.state == .awaitingInput,
      let request = questions.requests.first(where: { $0.runId == run.id }),
      !request.questions.contains(where: { $0.isSecret == true }) else { return [] }
    return request.questions.compactMap { question in
      guard let options = question.options, options.count >= 2 else { return nil }
      let choice = MessagesDecisionChoices.Choice.question(runID: run.id, requestID: request.id, questionID: question.id)
      let code = choices.code(for: choice)
      let descriptions = options.compactMap { option in
        option.description.map { "\(option.label): \($0)" }
      }.joined(separator: "\n")
      return MessagesPollDecision.make(target: .native(code: code, choice: choice), heading: heading,
        question: question.question, options: options.map(\.label),
        detail: descriptions.isEmpty ? nil : descriptions, lifetime: 86_400,
        requestFingerprint: requestFingerprint(for: choice))
    }
  }

  private func requestFingerprint(for choice: MessagesDecisionChoices.Choice) -> String? {
    switch choice {
    case .approval(let runID, let requestID):
      guard let approval = runs.first(where: { $0.id == runID })?.approval, approval.id == requestID else { return nil }
      return MessagesPollDecision.fingerprint([runID, requestID, approval.command, approval.description])
    case .question(let runID, let requestID, let questionID):
      guard let request = questions.requests.first(where: { $0.runId == runID && $0.id == requestID }),
        let question = request.questions.first(where: { $0.id == questionID }) else { return nil }
      let details = (question.options ?? []).flatMap { [$0.label, $0.description ?? ""] }
      return MessagesPollDecision.fingerprint([runID, requestID, questionID, question.question] + details)
    }
  }

}
