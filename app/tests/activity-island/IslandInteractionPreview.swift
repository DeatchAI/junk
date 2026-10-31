import AppKit
import CoreText
import SwiftUI

enum AppSettings {
  static let notchLiveActivitiesEnabled = true
  static let activityIslandPlacement = ActivityIslandPlacement.right
}

/// Runs production windowing and views against isolated, explicitly fictional tasks.
@main
struct IslandInteractionPreview {
  @MainActor static func main() {
    let app = NSApplication.shared
    app.setActivationPolicy(.regular)
    UserDefaults.standard.setVolatileDomain([
      "appearance_preset": ThemePreset.lazzydark.rawValue,
      "appearance_mode": AppearanceMode.solid.rawValue,
    ], forName: UserDefaults.argumentDomain)
    ThemeManager.shared.refreshFromSettings()
    let fixture = NotchInteractionFixture()
    fixture.start()
    app.run()
    withExtendedLifetime(fixture) {}
  }
}

@MainActor
private final class NotchInteractionFixture: NSObject, ObservableObject, NSWindowDelegate {
  let store = DetachedRunStore()
  let controls = DetachedRunControls()
  let questions = AgentQuestionCenter.shared
  lazy var island = ActivityIslandWindowController(runStore: store, controls: controls)
  private var window: NSWindow?
  private var managers: [WebSocketManager] = []
  @Published var replies: [String] = []

  func start() {
    questions.configure(runStore: store, island: island)
    for (id, agent, title, status) in [
      ("review", "codex", "Review the release changes", "Reading authentication changes"),
      ("build", "claude", "Fix the Mac app build", "Running focused tests"),
      ("guide", "pi", "Update the setup guide", "Reading provider instructions"),
      ("search", "amp", "Improve project search", "Checking the index"),
      ("test", "omp", "Fix the failing tests", "Checking test output"),
    ] { add(id, agent: agent, title: title, status: status) }
    for index in 1...6 {
      add("extra-\(index)", agent: "opencode", title: "Background task \(index)", status: "Reading source files")
    }
    ask("review", prompt: "Which area should I review first?")
    store.requestApproval(id: "preview-approval", runId: "build", conversationId: "chat-build",
      command: "git push origin release/mac-app", description: "Push the release branch to the remote repository?", riskLevel: "high")
    island.onApprovalResponse = { [weak self] id, approved in
      DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
        self?.replies.append("\(id): \(approved ? "approved" : "denied")")
        self?.store.resolveApproval(id: id)
      }
    }
    island.onOpenConversation = { [weak self] id in self?.replies.append("Opened \(id)") }
    let panel = NSWindow(contentRect: NSRect(x: 160, y: 240, width: 380, height: 310),
      styleMask: [.titled, .closable], backing: .buffered, defer: false)
    panel.title = "Detach notch interaction preview"
    panel.delegate = self
    panel.isReleasedWhenClosed = false
    panel.contentView = NSHostingView(rootView: dashboard.padding(22))
    panel.orderFrontRegardless()
    window = panel
    island.show()
    print("Native notch fixture ready; no provider requests or external actions are performed.")
  }

  private var dashboard: some View {
    VStack(alignment: .leading, spacing: 14) {
      Text("Native notch interaction preview").font(.headline)
      Text("Fictional tasks using the production panel, rows, and reply handling.")
        .font(.caption).foregroundStyle(.secondary)
      Button("Reveal tasks") { self.island.toggleExpanded() }
      Button("Add Amp question") { self.ask("search", prompt: "Which search scope should I use?") }
      Button("Complete running tasks") {
        for run in self.store.activeRuns where !run.needsAttention {
          self.store.complete(runId: run.id, conversationId: run.conversationId ?? run.id)
        }
      }
      Button("Clear tasks") {
        self.questions.cancel(owner: ObjectIdentifier(self))
        self.store.showDebugScenario(.clear)
      }
      FixtureReplies(fixture: self)
    }.frame(maxWidth: .infinity, alignment: .leading)
  }

  private func add(_ id: String, agent: String, title: String, status: String) {
    let request = ChatRequest(text: title, runId: id, conversationId: "chat-\(id)", workspacePath: "/Projects/Detach", agent: agent)
    store.begin(request)
    store.apply(.init(runId: id, conversationId: "chat-\(id)", status: status, toolName: nil, event: nil))
    let manager = WebSocketManager()
    manager.activeChatRequest = request
    manager.currentConversationId = "chat-\(id)"
    managers.append(manager)
    controls.register(request, manager: manager)
  }

  private func ask(_ id: String, prompt: String) {
    guard !questions.requests.contains(where: { $0.runId == id }) else { return }
    let run = store.runs.first { $0.id == id }!
    let data = try! JSONSerialization.data(withJSONObject: [
      "type": "agent_question", "id": "preview-\(id)", "runId": id,
      "conversationId": "chat-\(id)", "agent": run.agent, "taskTitle": run.taskTitle,
      "questions": [["id": "scope", "header": "Scope", "question": prompt,
        "options": [["label": "Mac app", "description": "Review the native interface"],
          ["label": "Runtime", "description": "Review provider handling"]]]],
    ])
    _ = questions.handle(data, owner: ObjectIdentifier(self)) { [weak self] response in
      guard let self else { return }
      self.replies.append("\(response.runId): \(response.cancelled ? "cancelled" : response.answers?["scope"]?.answers.first ?? "")")
      DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
        let resolved = try! JSONSerialization.data(withJSONObject: [
          "type": "agent_question_resolved", "id": response.requestId, "runId": response.runId,
        ])
        _ = self.questions.handle(resolved, owner: ObjectIdentifier(self)) { _ in }
      }
    }
  }

  func windowWillClose(_ notification: Notification) { NSApp.terminate(nil) }
}

private struct FixtureReplies: View {
  @ObservedObject var fixture: NotchInteractionFixture
  var body: some View {
    Text(fixture.replies.last ?? "No replies sent").font(.caption).lineLimit(3)
      .frame(maxWidth: .infinity, alignment: .leading)
  }
}
