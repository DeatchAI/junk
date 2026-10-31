import AppKit
import Combine
import SwiftUI

/// Keeps questions and drafts alive independently of floating chat windows.
@MainActor
final class AgentQuestionCenter: ObservableObject {
  static let shared = AgentQuestionCenter()
  @Published private(set) var requests: [AgentQuestionEnvelope] = []
  @Published private(set) var drafts: [String: [String: String]] = [:]
  @Published private(set) var submitting: Set<String> = []
  @Published private(set) var errors: [String: String] = [:]
  @Published private(set) var pages: [String: Int] = [:]

  private struct Destination {
    let owner: ObjectIdentifier
    let respond: (AgentQuestionResponse) -> Void
  }
  private var destinations: [String: Destination] = [:]
  private var visibleComposers: Set<ObjectIdentifier> = []
  private var conversationTitles: [String: String] = [:]
  private weak var runStore: DetachedRunStore?
  private weak var island: ActivityIslandWindowController?
  private var window: NSPanel?
  private var displayedRequestID: String?
  private var preferences: AnyCancellable?
  var current: AgentQuestionEnvelope? { requests.first }

  func question(for owner: ObjectIdentifier) -> AgentQuestionEnvelope? {
    requests.first { destinations[$0.id]?.owner == owner }
  }

  func setComposerVisible(_ visible: Bool, for owner: ObjectIdentifier) {
    if visible { visibleComposers.insert(owner) }
    else { visibleComposers.remove(owner) }
    presentIfNeeded()
  }

  var standaloneQuestion: AgentQuestionEnvelope? {
    requests.first { request in
      guard let owner = destinations[request.id]?.owner else { return false }
      return !visibleComposers.contains(owner)
    }
  }

  func showQuestion(_ id: String) {
    guard let index = requests.firstIndex(where: { $0.id == id }) else { return }
    let request = requests.remove(at: index)
    requests.insert(request, at: 0)
    presentIfNeeded()
    if AppSettings.notchLiveActivitiesEnabled { island?.focusQuestion() }
    else if standaloneQuestion != nil { window?.makeKeyAndOrderFront(nil) }
  }

  func configure(runStore: DetachedRunStore, island: ActivityIslandWindowController) {
    self.runStore = runStore
    self.island = island
    preferences = NotificationCenter.default.publisher(for: UserDefaults.didChangeNotification)
      .receive(on: RunLoop.main)
      .sink { [weak self] _ in self?.presentIfNeeded() }
  }

  func handle(_ data: Data, owner: ObjectIdentifier, respond: @escaping (AgentQuestionResponse) -> Void) -> Bool {
    guard let message = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
      let type = message["type"] as? String,
      ["agent_question", "agent_question_resolved", "agent_question_error"].contains(type)
    else { return false }
    if type == "agent_question", let decoded = try? JSONDecoder().decode(AgentQuestionEnvelope.self, from: data),
      case let request = named(decoded),
      !request.questions.isEmpty, request.questions.count <= 3, destinations[request.id] == nil
    {
      destinations[request.id] = Destination(owner: owner, respond: respond)
      requests.append(request)
      runStore?.waitForAnswer(runId: request.runId, question: request.questions.first?.question,
        conversationId: request.conversationId, agent: request.agent, taskTitle: request.taskTitle)
      presentIfNeeded()
    } else if let id = message["id"] as? String, destinations[id]?.owner == owner {
      if type == "agent_question_error" {
        submitting.remove(id)
        errors[id] = message["error"] as? String ?? "Please answer each question."
      } else if type == "agent_question_resolved" { remove(id) }
    }
    return true
  }

  func updateConversationTitle(conversationId: String, title: String) {
    guard conversationTitles[conversationId] != title else { return }
    conversationTitles[conversationId] = title
    requests = requests.map(named)
  }

  private func named(_ request: AgentQuestionEnvelope) -> AgentQuestionEnvelope {
    guard let title = conversationTitles[request.conversationId] else { return request }
    return .init(id: request.id, runId: request.runId, conversationId: request.conversationId,
      agent: request.agent, taskTitle: title, questions: request.questions)
  }

  func setAnswer(_ text: String, questionID: String, requestID: String) {
    drafts[requestID, default: [:]][questionID] = text
    errors[requestID] = nil
  }

  func answer(for question: AgentQuestion, in request: AgentQuestionEnvelope) -> String {
    drafts[request.id]?[question.id] ?? ""
  }

  func page(for request: AgentQuestionEnvelope) -> Int {
    min(max(pages[request.id] ?? 0, 0), max(request.questions.count - 1, 0))
  }

  func setPage(_ page: Int, for request: AgentQuestionEnvelope) {
    pages[request.id] = min(max(page, 0), max(request.questions.count - 1, 0))
  }

  func submit(_ request: AgentQuestionEnvelope, cancelled: Bool = false) {
    guard !submitting.contains(request.id), let destination = destinations[request.id] else { return }
    var answers: [String: AgentQuestionResponse.Answer] = [:]
    if !cancelled {
      for question in request.questions {
        let value = answer(for: question, in: request).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return }
        answers[question.id] = .init(answers: [value])
      }
    }
    submitting.insert(request.id)
    destination.respond(.init(requestId: request.id, runId: request.runId,
      answers: cancelled ? nil : answers, cancelled: cancelled))
  }

  func cancel(owner: ObjectIdentifier) {
    for id in requests.filter({ destinations[$0.id]?.owner == owner }).map(\.id) { remove(id) }
  }

  private func remove(_ id: String) {
    let runId = requests.first(where: { $0.id == id })?.runId
    requests.removeAll { $0.id == id }
    destinations[id] = nil
    drafts[id] = nil
    pages[id] = nil
    submitting.remove(id)
    errors[id] = nil
    if let runId, !requests.contains(where: { $0.runId == runId }) { runStore?.resumeAfterAnswer(runId: runId) }
    if current == nil { window?.orderOut(nil) }
    else { presentIfNeeded() }
    island?.show()
  }

  private func presentIfNeeded() {
    // A visible composer must not suppress the ambient interruption surface.
    if AppSettings.notchLiveActivitiesEnabled && !requests.isEmpty {
      window?.orderOut(nil)
      island?.showApproval()
      return
    }
    guard let request = standaloneQuestion else {
      window?.orderOut(nil)
      return
    }
    if window == nil {
      let panel = AgentQuestionPanel(contentRect: NSRect(x: 0, y: 0, width: 420, height: 380),
        styleMask: [.titled, .closable, .nonactivatingPanel], backing: .buffered, defer: false)
      panel.title = "Agent question"
      panel.isOpaque = false
      panel.backgroundColor = .clear
      panel.titlebarAppearsTransparent = true
      panel.isFloatingPanel = true
      panel.hidesOnDeactivate = false
      panel.isReleasedWhenClosed = false
      panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
      panel.center()
      window = panel
    }
    if displayedRequestID != request.id {
      window?.contentView = NSHostingView(rootView: AgentQuestionForm(center: self, requestID: request.id)
        .padding(20).themedSurface(in: Rectangle()))
      displayedRequestID = request.id
    }
    window?.orderFrontRegardless()
  }
}

final class AgentQuestionPanel: NSPanel {
  // Ambient panels opt out until an explicit click; standalone reply windows stay keyable.
  var allowsKeyFocus = true
  override var canBecomeKey: Bool { allowsKeyFocus }
}
