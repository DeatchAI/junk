import Foundation

// Lightweight collaborators keep this a state/contract test, without opening UI.
enum AppSettings { @MainActor static let notchLiveActivitiesEnabled = true }
final class DetachedRunStore {
  var waiting: Set<String> = []
  func waitForAnswer(runId: String, question: String? = nil) { waiting.insert(runId) }
  func resumeAfterAnswer(runId: String) { waiting.remove(runId) }
}
final class ActivityIslandWindowController {
  func showApproval() {}
  func show() {}
  func focusQuestion() {}
}

@main
struct QuestionStateTests {
  @MainActor static func main() throws {
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
    center.setComposerVisible(true, for: ObjectIdentifier(owner))
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
    assert(center.current == nil && center.drafts.isEmpty && store.waiting.isEmpty)
    _ = center.handle(data, owner: ObjectIdentifier(owner)) { responses.append($0) }
    center.cancel(owner: ObjectIdentifier(otherOwner))
    assert(center.current != nil)
    center.cancel(owner: ObjectIdentifier(owner))
    assert(center.current == nil && store.waiting.isEmpty)
    print("Question state and wire-contract checks passed")
  }
}
