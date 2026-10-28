import AppKit
import SwiftUI
@testable import Detach

/// Real production views with isolated preferences and synthetic tasks, never an agent run.
@MainActor private struct ImprovementsPreview: View {
  @State private var page = "Results"
  @State private var selectedAgent = "codex"
  @StateObject private var setup = AgentSetupModel(states: [
    .codex: AgentReadiness(state: .ready, detail: "Sign-in confirmed. A first task checks that your agent can respond."),
    .claude: AgentReadiness(state: .signInNeeded, detail: "Sign in with your agent, then check again."),
    .opencode: .installed,
    .grok: AgentReadiness(state: .missing, detail: "Install Grok to connect."),
    .fx: AgentReadiness(state: .missing, detail: "Install fx to connect."),
    .pi: AgentReadiness(state: .missing, detail: "Install Pi to connect."),
    .amp: AgentReadiness(state: .missing, detail: "Install Amp to connect."),
    .omp: AgentReadiness(state: .missing, detail: "Install Omp to connect."),
  ])
  @ObservedObject var manager: WebSocketManager
  @ObservedObject var store: DetachedRunStore
  @ObservedObject var controls: DetachedRunControls

  var body: some View {
    VStack(spacing: 0) {
      Picker("Preview", selection: $page) {
        ForEach(["Results", "Setup", "Settings"], id: \.self) { Text($0).tag($0) }
      }.pickerStyle(.segmented).frame(width: 360).padding(16)
      Divider()
      if page == "Results" {
        ActivityIslandTaskList(store: store, controls: controls, questions: AgentQuestionCenter.shared,
          onOpenConversation: { store.markReviewed(conversationId: $0) }, onApprovalResponse: { _, _ in })
          .padding(24).frame(width: 560, height: 430)
        Text("Synthetic tasks · opening a result acknowledges it").font(.system(size: 12)).foregroundStyle(.secondary)
      } else if page == "Setup" {
        VStack(alignment: .leading, spacing: 18) {
          Text("Choose your agent").font(.system(size: 26, weight: .semibold))
          AgentSetupList(setup: setup, selectedAgent: $selectedAgent)
        }.padding(30).frame(width: 570)
      } else {
        SettingsView(wsManager: manager)
      }
      Spacer(minLength: 0)
    }
    .frame(width: 940, height: 760)
    .background(Color.black).foregroundStyle(.white).tint(.white).preferredColorScheme(.dark)
  }
}

@MainActor final class ImprovementsPreviewDelegate: NSObject, NSApplicationDelegate {
  private var window: NSWindow?
  private var manager: WebSocketManager?
  func applicationDidFinishLaunching(_ notification: Notification) {
    UserDefaults.standard.setVolatileDomain([
      "appearance_preset": "Lazzy Dark", "appearance_mode": "Solid",
      "appearance_bg_color": "#000000", "appearance_fg_color": "#FFFFFF",
    ], forName: UserDefaults.argumentDomain)
    ThemeManager.shared.refreshFromSettings()
    let manager = WebSocketManager()
    manager.isConnecting = true; manager.session?.invalidateAndCancel(); manager.session = nil
    self.manager = manager
    let store = DetachedRunStore(), controls = DetachedRunControls()
    store.begin(ChatRequest(text: "Polish the composer", runId: "done", workspacePath: "/Projects/Detach", agent: "codex"))
    store.apply(AgentActivityUpdate(runId: "done", conversationId: "done-chat", status: "Updated files", toolName: nil,
      event: AgentActivityEvent(id: "file", agent: "codex", kind: "file_change", action: nil, phase: "completed",
        title: "Updated composer", subtitle: nil, toolName: nil, userFacing: true,
        sourceEventType: nil, sourceItemType: nil, details: ["path": .string("Composer.swift")])))
    store.complete(runId: "done", conversationId: "done-chat")
    store.begin(ChatRequest(text: "Review the pricing page", runId: "working", workspacePath: "/Projects/Website", agent: "claude"))
    let root = ImprovementsPreview(manager: manager, store: store, controls: controls)
    let window = NSWindow(contentRect: NSRect(x: 160, y: 100, width: 940, height: 760),
      styleMask: [.titled, .closable], backing: .buffered, defer: false)
    window.title = "Detach improvements · isolated native preview"
    window.contentView = NSHostingView(rootView: root)
    window.isReleasedWhenClosed = false; window.makeKeyAndOrderFront(nil)
    NSApp.activate(ignoringOtherApps: true)
    self.window = window
  }
}

@main struct ImprovementsPreviewApp {
  @MainActor static func main() {
    let application = NSApplication.shared
    let delegate = ImprovementsPreviewDelegate()
    application.delegate = delegate; application.setActivationPolicy(.regular)
    application.run()
    withExtendedLifetime(delegate) {}
  }
}
