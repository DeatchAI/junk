import AppKit
import Foundation
import SwiftUI

enum AppSettings {
  static let notchLiveActivitiesEnabled = true
  static let activityIslandPlacement: ActivityIslandPlacement = {
    // Keep the synthetic panel away from the current pointer without moving it.
    NSEvent.mouseLocation.x > (NSScreen.main?.frame.midX ?? 700) ? .left : .right
  }()
}

/// Uses the production AppKit controller and SwiftUI views with isolated fictional runs.
@main
struct IslandPresentationTests {
  @MainActor static func main() {
    let app = NSApplication.shared
    app.setActivationPolicy(.accessory)
    Task { @MainActor in
      await exercise()
      NSApp.terminate(nil)
    }
    app.run()
  }

  @MainActor private static func exercise() async {
    let store = DetachedRunStore()
    let controls = DetachedRunControls()
    let island = ActivityIslandWindowController(runStore: store, controls: controls)
    let questions = AgentQuestionCenter.shared
    let owner = NSObject()
    var approvalReplies = 0
    var questionReplies = 0
    island.onApprovalResponse = { _, _ in approvalReplies += 1 }
    questions.configure(runStore: store, island: island)
    defer { questions.cancel(owner: ObjectIdentifier(owner)); island.hide() }

    store.begin(ChatRequest(text: "Native reveal test", runId: "run-a", conversationId: "chat-a", agent: "codex"))
    island.show()
    expect(island.isVisible && island.isExpanded, "New activity must expand without hovering")
    let window = NSApp.windows.compactMap { $0 as? AgentQuestionPanel }.first!
    // Do not let real desktop clicks answer these fictional permission requests.
    window.ignoresMouseEvents = true
    await pause(0.45)
    expect(window.frame.width > ActivityIslandLayout.compactSideSize.width, "The actual native panel must grow")
    expect(!window.isKeyWindow, "Automatic activity must not steal keyboard focus")
    island.setHovering(false)
    await pause(0.5)
    expect(island.isExpanded, "A synthetic hover exit must not undo a fresh activity reveal")
    await pause(ActivityIslandWindowController.activityRevealDuration)
    if !window.frame.contains(NSEvent.mouseLocation) {
      expect(!island.isExpanded, "Idle work may return to compact after the reveal interval")
    }
    store.apply(.init(runId: "run-a", conversationId: "chat-a", status: "Reading the next file", toolName: nil, event: nil))
    island.show()
    expect(island.isExpanded, "The next streamed activity must reveal the panel again")
    _ = island.beginComposerHandoff()
    expect(island.isExpanded, "Closing the composer must not suppress a fresh activity")
    print("Native activity reveal, idle collapse, composer handoff, and focus preservation passed")

    store.requestApproval(id: "approval-a", runId: "run-a", conversationId: "chat-a",
      command: "printf native-notch-test", description: "Synthetic permission request", riskLevel: "normal")
    island.showApproval()
    expect(island.isExpanded && island.interaction.expandedRunID == "run-a",
      "An approval must expose its actions inline immediately")
    island.setHovering(false)
    await pause(ActivityIslandWindowController.activityRevealDuration + 0.4)
    expect(island.isVisible && island.isExpanded, "Pending approvals must outlive the normal activity reveal")
    expect(approvalReplies == 0, "Revealing an approval must not send a decision")
    expect(!window.isKeyWindow, "Revealing an approval must not take keyboard focus")
    store.resolveApproval(id: "approval-a")

    // Reproduce a question arriving while its composer is visible and the notch is hidden.
    island.hide()
    store.begin(ChatRequest(text: "Native question test", runId: "run-b", conversationId: "chat-b", agent: "pi"))
    questions.setComposerVisible(true, for: ObjectIdentifier(owner))
    let data = try! JSONSerialization.data(withJSONObject: [
      "type": "agent_question", "id": "question-b", "runId": "run-b", "conversationId": "chat-b",
      "agent": "pi", "taskTitle": "Native question test",
      "questions": [["id": "scope", "header": "Scope", "question": "Which scope?",
        "options": [["label": "Mac app"], ["label": "Runtime"]]]],
    ])
    _ = questions.handle(data, owner: ObjectIdentifier(owner)) { _ in questionReplies += 1 }
    expect(island.isVisible && island.isExpanded && island.interaction.expandedRunID == "run-b",
      "A visible composer must not suppress the notch or its question")
    let request = questions.current!
    questions.setAnswer("Keep this draft", questionID: "scope", requestID: request.id)
    await pause(0.8)
    expect((island.interaction.expandedInteractionHeight ?? 999) <= 200,
      "A short question must fit its content without reserving the old blank body space")
    expect(!window.isKeyWindow, "An automatic question must not take keyboard focus")
    island.focusForInteraction()
    expect(window.isKeyWindow, "An explicit interaction must enable native keyboard input")
    window.resignKey()
    window.allowsKeyFocus = false

    store.begin(ChatRequest(text: "Other agent", runId: "run-c", conversationId: "chat-c", agent: "amp"))
    store.requestApproval(id: "approval-c", runId: "run-c", conversationId: "chat-c",
      command: "printf another-fixture", description: "Another synthetic request", riskLevel: "normal")
    island.showApproval()
    expect(island.interaction.expandedRunID == "run-b",
      "A second interruption must not replace a question being answered")
    expect(questions.answer(for: request.questions[0], in: request) == "Keep this draft",
      "Concurrent interruptions must preserve the draft")
    expect(store.presentationRuns.count == 3 && approvalReplies == 0 && questionReplies == 0,
      "Automatic presentation must keep one row per task and send no responses")
    let resolved = try! JSONSerialization.data(withJSONObject: [
      "type": "agent_question_resolved", "id": "question-b", "runId": "run-b",
    ])
    _ = questions.handle(resolved, owner: ObjectIdentifier(owner)) { _ in }
    await pause(0.2)
    expect(island.isExpanded && island.interaction.expandedRunID == "run-c",
      "Resolving one interruption must expose the next pending request")
    expect(island.interaction.expandedInteractionHeight == nil,
      "The next approval must not inherit the previous question's height")
    print("Native approval visibility, visible-composer questions, concurrent drafts, and explicit-only responses passed")
  }

  @MainActor private static func pause(_ seconds: TimeInterval) async {
    try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
  }

  private static func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
    precondition(condition(), message)
  }
}
