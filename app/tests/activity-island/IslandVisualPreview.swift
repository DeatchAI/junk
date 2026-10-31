import AppKit
import CoreText
import SwiftUI

enum AppSettings { @MainActor static let notchLiveActivitiesEnabled = true }
@MainActor final class ActivityIslandWindowController: ObservableObject {
  @Published var isExpanded = true
  @Published var placement = ActivityIslandPlacement.right
  @Published var physicalNotchHeight: CGFloat = 40
  let interaction = ActivityIslandTaskState()
  func setHovering(_ hovering: Bool) {}
  func showApproval() {}
  func show() {}
  func focusQuestion() {}
  func focusForInteraction() {}
  func collapse() { interaction.collapse(); isExpanded = false }
}

/// Offscreen component rendering, not a screenshot of an installed/live app.
@main
struct IslandVisualPreview {
  @MainActor static func main() throws {
    _ = NSApplication.shared
    for name in ["AppIcon", "ProviderCodex", "ProviderClaude", "ProviderGrok", "ProviderFx", "ProviderOpenCode", "ProviderPi", "ProviderAmp", "ProviderOmp"] {
      _ = NSImage(named: name)?.tiffRepresentation
    }
    if let font = Bundle.main.url(forResource: "Geist-Regular", withExtension: "ttf") {
      CTFontManagerRegisterFontsForURL(font as CFURL, .process, nil)
    }
    let output = CommandLine.arguments[1]
    let variant = CommandLine.arguments.count > 2 ? CommandLine.arguments[2] : "dark"
    let preset: ThemePreset = variant == "light" ? .lazzywhite : variant == "custom" ? .custom : .lazzydark
    UserDefaults.standard.setVolatileDomain([
      "appearance_preset": preset.rawValue,
      "appearance_mode": (variant == "glass" ? AppearanceMode.liquidGlass : .solid).rawValue,
      "appearance_bg_color": "#161616", "appearance_fg_color": "#D3D3D3", "appearance_accent_color": "#FFFFFF",
    ], forName: UserDefaults.argumentDomain)
    ThemeManager.shared.refreshFromSettings()
    let store = DetachedRunStore(), controls = DetachedRunControls(), questions = AgentQuestionCenter.shared
    let island = ActivityIslandWindowController()
    var managers: [WebSocketManager] = []
    func add(_ id: String, _ agent: String, _ prompt: String, _ status: String) {
      let request = ChatRequest(text: prompt, runId: id, conversationId: "chat-\(id)", workspacePath: id == "docs" ? "/Projects/Website" : "/Projects/Detach", agent: agent)
      store.begin(request)
      store.apply(.init(runId: id, conversationId: "chat-\(id)", status: status, toolName: nil, event: nil))
      let manager = WebSocketManager()
      manager.activeChatRequest = request
      manager.currentConversationId = "chat-\(id)"
      managers.append(manager)
      controls.register(request, manager: manager)
    }
    func render(_ name: String, question: Bool = false, approval: Bool = false, save: Bool = true, scrollToBottom: Bool = false) throws {
      island.interaction.reconcile(store.presentationRuns)
      if let run = store.presentationRuns.first(where: { question ? $0.state == .awaitingInput : approval && $0.approval != nil }) {
        island.interaction.select(run)
      } else { island.interaction.collapse() }
      func panelFrame() -> CGRect {
        let size = ActivityIslandContentLayout.size(taskCount: store.presentationRuns.count,
          hasQuestion: question, hasApproval: approval, hasCredential: false,
          sectionCount: Set(store.presentationRuns.map { ActivityIslandTaskState.section(for: $0) }).count,
          interactionHeight: island.interaction.expandedInteractionHeight)
        return ActivityIslandLayout.frame(placement: island.placement,
          screenFrame: CGRect(x: 0, y: 0, width: 1512, height: 982),
          visibleFrame: CGRect(x: 0, y: 0, width: 1512, height: 950),
          physicalNotch: CGSize(width: 200, height: island.physicalNotchHeight), expanded: island.isExpanded,
          contentSize: size)
      }
      func content(_ size: CGSize) -> some View {
        ActivityIslandView(store: store, controller: island, controls: controls, interaction: island.interaction,
          onToggle: {}, onOpenConversation: { _ in }, onApprovalResponse: { _, _ in })
          .frame(width: size.width, height: size.height)
      }
      var frame = panelFrame()
      // ImageRenderer deliberately omits platform-backed scroll/field content.
      // Cache an actual hosting view instead, without presenting a desktop window.
      let host = NSHostingView(rootView: content(frame.size))
      var bounds = NSRect(origin: .zero, size: frame.size)
      let window = NSWindow(contentRect: bounds, styleMask: .borderless, backing: .buffered, defer: false)
      window.contentView = host
      host.frame = bounds
      host.layoutSubtreeIfNeeded()
      RunLoop.current.run(until: Date().addingTimeInterval(0.8))
      let fitted = panelFrame()
      if fitted.size != frame.size {
        frame = fitted
        bounds.size = fitted.size
        host.rootView = content(fitted.size)
        window.setContentSize(fitted.size)
        host.frame = bounds
        host.layoutSubtreeIfNeeded()
        RunLoop.current.run(until: Date().addingTimeInterval(0.3))
      }
      if scrollToBottom {
        func scrollViews(in view: NSView) -> [NSScrollView] {
          let own = (view as? NSScrollView).map { [$0] } ?? []
          return own + view.subviews.flatMap { scrollViews(in: $0) }
        }
        if let scroll = scrollViews(in: host).max(by: { $0.bounds.height < $1.bounds.height }),
          let document = scroll.documentView {
          let y = document.isFlipped ? max(0, document.bounds.height - scroll.contentView.bounds.height) : 0
          scroll.contentView.scroll(to: NSPoint(x: 0, y: y))
          scroll.reflectScrolledClipView(scroll.contentView)
          host.layoutSubtreeIfNeeded()
          RunLoop.current.run(until: Date().addingTimeInterval(0.3))
        }
      }
      guard let bitmap = host.bitmapImageRepForCachingDisplay(in: bounds)
      else { fatalError("Unable to create native bitmap") }
      host.cacheDisplay(in: bounds, to: bitmap)
      guard let png = bitmap.representation(using: .png, properties: [:])
      else { fatalError("Unable to render native notch components") }
      if save {
        try png.write(to: URL(fileURLWithPath: output).appendingPathComponent("\(name)-\(variant).png"))
        print("Rendered \(name)-\(variant): \(Int(frame.width)) × \(Int(frame.height)) points")
      }
      withExtendedLifetime(window) {}
    }
    add("review", "codex", "Review the release changes", "Reading the authentication changes")
    try render("single-task-warmup", save: false)
    try render("single-task")
    add("pi", "pi", "Review the project structure", "Reading the source files")
    add("amp", "amp", "Improve the search experience", "Checking the implementation")
    add("omp", "omp", "Fix the failing tests", "Running the focused test suite")
    add("build", "claude", "Fix the Mac app build", "Running the focused test suite")
    add("docs", "opencode", "Update the setup guide", "Editing the provider instructions")
    add("cache", "fx", "Speed up project indexing", "Checking the cache strategy")
    add("search", "grok", "Check the release notes", "Reviewing the latest changes")
    add("checklist", "pi", "Draft a launch checklist", "Organizing the remaining checks")
    // The first offscreen draw uploads asset-catalog textures; capture a fresh
    // hosting tree afterward so cold-process previews include every provider mark.
    try render("asset-warmup", save: false)
    try render("tasks")
    store.requestApproval(id: "approval", runId: "build", conversationId: "chat-build",
      command: "git push origin release/mac-app", description: "Push the verified release branch to the remote repository?",
      riskLevel: "high")
    try render("approval", approval: true)
    store.resolveApproval(id: "approval")
    let questionData = try JSONSerialization.data(withJSONObject: [
      "type": "agent_question", "id": "clarify", "runId": "review", "conversationId": "chat-review",
      "agent": "codex", "taskTitle": "Review the release changes",
      "questions": [["id": "scope", "header": "Scope", "question": "Which part should I review first?",
        "options": [
          ["label": "Mac app", "description": "Check the native interface and task lifecycle"],
          ["label": "Runtime", "description": "Check provider adapters and permission handling"],
        ]]],
    ])
    questions.configure(runStore: store, island: island)
    _ = questions.handle(questionData, owner: ObjectIdentifier(island)) { _ in }
    try render("question", question: true)
    questions.cancel(owner: ObjectIdentifier(island))
    store.requestStop(runId: "review")
    store.complete(runId: "review", conversationId: "chat-review")
    let stoppedManager = managers.first { $0.activeChatRequest?.runId == "review" }!
    stoppedManager.isStreaming = false
    stoppedManager.isStoppingRun = false
    try render("stopped")
    store.complete(runId: "docs", conversationId: "chat-docs")
    for id in ["pi", "amp", "build", "cache", "search", "checklist"] {
      store.complete(runId: id, conversationId: "chat-\(id)")
      store.markReviewed(conversationId: "chat-\(id)")
    }
    try render("unread-result")

    // Exactly ten independent tasks: three approvals, two questions, five running.
    store.showDebugScenario(.clear)
    managers.removeAll()
    add("review", "codex", "Review authentication changes", "Reading the sign-in flow")
    add("build", "claude", "Prepare the Mac app release", "Checking release settings")
    add("pi", "pi", "Refine the project structure", "Reviewing source folders")
    add("amp", "amp", "Improve project search", "Checking the search index")
    add("docs", "opencode", "Update the setup guide", "Editing provider instructions")
    add("omp", "omp", "Fix the failing tests", "Running the focused test suite")
    add("cache", "fx", "Speed up project indexing", "Checking the cache strategy")
    add("browser", "grok", "Check the landing page", "Inspecting the mobile layout")
    add("checklist", "pi", "Draft a launch checklist", "Organizing remaining checks")
    add("release", "claude", "Write the release notes", "Summarizing the latest changes")
    for (id, command, description, risk) in [
      ("build", "xcodebuild -scheme Detach -configuration Release build", "Build the release app?", "normal"),
      ("amp", "npm install fuse.js", "Install the search dependency?", "normal"),
      ("docs", "git push origin docs/setup-guide", "Push the updated setup guide?", "high"),
    ] {
      store.requestApproval(id: "busy-approval-\(id)", runId: id, conversationId: "chat-\(id)",
        command: command, description: description, riskLevel: risk)
    }
    for (id, agent, prompt, first, second) in [
      ("review", "codex", "Which area should I review first?", "Sign-in flow", "Session handling"),
      ("pi", "pi", "How should I organize the source?", "Keep current folders", "Group by module"),
    ] {
      let data = try JSONSerialization.data(withJSONObject: [
        "type": "agent_question", "id": "busy-question-\(id)", "runId": id,
        "conversationId": "chat-\(id)", "agent": agent,
        "taskTitle": store.runs.first(where: { $0.id == id })!.taskTitle,
        "questions": [["id": "choice", "header": "Scope", "question": prompt,
          "options": [["label": first], ["label": second]]]],
      ])
      _ = questions.handle(data, owner: ObjectIdentifier(island)) { _ in }
    }
    precondition(store.visibleActiveRuns.count == 10)
    precondition(store.visibleActiveRuns.filter(\.needsAttention).count == 5)
    precondition(store.visibleActiveRuns.filter { $0.state == .running }.count == 5)
    try render("ten-agents-overview")
    try render("ten-agents-question", question: true)
    try render("ten-agents-approval", approval: true)
    try render("ten-agents-running", scrollToBottom: true)
    questions.cancel(owner: ObjectIdentifier(island))
    withExtendedLifetime(managers) {}
  }
}
