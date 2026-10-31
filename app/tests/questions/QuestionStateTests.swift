import Foundation
import AppKit

// Lightweight collaborators keep this a state/contract test, without opening UI.
enum AppSettings { @MainActor static let notchLiveActivitiesEnabled = true }
final class DetachedRunStore {
  var waiting: Set<String> = []
  func waitForAnswer(runId: String, question: String? = nil, conversationId: String? = nil,
    agent: String? = nil, taskTitle: String? = nil) { waiting.insert(runId) }
  func resumeAfterAnswer(runId: String) { waiting.remove(runId) }
}
final class ActivityIslandWindowController {
  private(set) var approvalPresentations = 0
  func showApproval() { approvalPresentations += 1 }
  func show() {}
  func focusQuestion() {}
}

@main
struct QuestionStateTests {
  @MainActor static func main() throws {
    keyboardChecks()
    let center = AgentQuestionCenter(), owner = NSObject(), otherOwner = NSObject()
    let store = DetachedRunStore(), island = ActivityIslandWindowController()
    center.configure(runStore: store, island: island)
    var responses: [AgentQuestionResponse] = []
    let data = try JSONSerialization.data(withJSONObject: [
      "type": "agent_question", "id": "q1", "runId": "run1", "conversationId": "chat1", "agent": "pi",
      "questions": [
        ["id": "project", "header": "Project", "question": "Which project?", "options": [["label": "Website"]]],
        ["id": "detail", "header": "Details", "question": "What should change?"],
      ],
    ])
    assert(center.handle(data, owner: ObjectIdentifier(owner)) { responses.append($0) })
    let request = center.current!
    assert(center.question(for: ObjectIdentifier(owner))?.id == request.id)
    assert(center.question(for: ObjectIdentifier(otherOwner)) == nil, "Only the owning composer shows its question")
    center.setComposerVisible(true, for: ObjectIdentifier(otherOwner))
    assert(center.standaloneQuestion?.id == request.id, "Unrelated composers cannot hide a question")
    let presentationsBeforeComposer = island.approvalPresentations
    center.setComposerVisible(true, for: ObjectIdentifier(owner))
    assert(island.approvalPresentations > presentationsBeforeComposer,
      "Questions must reveal the notch even when their composer is visible")
    assert(center.standaloneQuestion == nil, "A visible composer presents its answer form inline")
    center.setComposerVisible(false, for: ObjectIdentifier(owner))
    assert(center.standaloneQuestion?.id == request.id, "Closing the composer restores the standalone question")
    assert(store.waiting.contains("run1"))
    center.updateConversationTitle(conversationId: "chat1", title: "Add Project Search")
    assert(center.current?.taskTitle == "Add Project Search")
    assert(center.current?.id == request.id, "Renaming must not reset the pending reply identity")
    center.submit(request)
    assert(responses.isEmpty, "A blank form must never submit default answers")
    center.setAnswer("My own project", questionID: "project", requestID: "q1")
    center.setPage(1, for: request)
    assert(center.page(for: request) == 1 && center.answer(for: request.questions[0], in: request) == "My own project",
      "The request owns its page and draft even when the inline form is recreated")
    center.submit(request)
    assert(responses.isEmpty, "Every question needs an answer")
    center.setAnswer("Add search", questionID: "detail", requestID: "q1")
    center.submit(request)
    center.submit(request)
    assert(responses.count == 1, "Repeated clicks must not send duplicate replies")
    assert(center.current != nil, "Keep the form until the runtime acknowledges it")
    let response = try JSONSerialization.jsonObject(with: JSONEncoder().encode(responses[0])) as! [String: Any]
    assert(response["type"] as? String == "agent_question_response")
    assert((response["answers"] as? [String: [String: [String]]])?["detail"]?["answers"] == ["Add search"])
    let resolved = try JSONSerialization.data(withJSONObject: ["type": "agent_question_resolved", "id": "q1", "runId": "run1"])
    _ = center.handle(resolved, owner: ObjectIdentifier(otherOwner)) { _ in }
    assert(center.current != nil, "Another task cannot dismiss this question")
    _ = center.handle(resolved, owner: ObjectIdentifier(owner)) { _ in }
    assert(center.current == nil && center.drafts.isEmpty && center.pages.isEmpty && store.waiting.isEmpty)
    _ = center.handle(data, owner: ObjectIdentifier(owner)) { responses.append($0) }
    center.cancel(owner: ObjectIdentifier(otherOwner))
    assert(center.current != nil)
    center.cancel(owner: ObjectIdentifier(owner))
    assert(center.current == nil && store.waiting.isEmpty)
    print("Question state and wire-contract checks passed")
  }

  private static func keyboardChecks() {
    func action(_ character: String, code: UInt16 = 18, modifiers: NSEvent.ModifierFlags = [],
      options: Int = 3, canContinue: Bool = true, editing: Bool = false) -> AgentQuestionKeyboardAction? {
      AgentQuestionKeyboardAction.resolve(characters: character, keyCode: code, modifiers: modifiers,
        optionCount: options, canContinue: canContinue, isEditingText: editing)
    }
    assert(action("1") == .select(0) && action("2") == .select(1) && action("3") == .select(2))
    assert(action("4") == nil && action("0") == nil && action("12") == nil)
    assert(action("1", modifiers: .command) == nil && action("1", modifiers: .control) == nil)
    assert(action("1", modifiers: .option) == nil && action("1", modifiers: .shift) == nil)
    assert(action("2", editing: true) == nil, "Numbers typed into custom/secure fields must remain text")
    assert(action("1", options: 0) == nil, "Free-text and secret questions have no option shortcuts")
    assert(action("\r", code: 36) == .continueAnswer)
    assert(action("\r", code: 36, canContinue: false) == nil, "Return never submits a blank answer")
    assert(action("\r", code: 36, editing: true) == nil, "Return remains native while editing text")
    assert(action("\u{1b}", code: 53) == nil, "Escape never cancels the task or chooses an answer")
  }
}
