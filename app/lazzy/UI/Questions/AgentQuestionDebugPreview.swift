#if DEBUG
import Foundation

extension AgentQuestionCenter {
  func clearDebugPreview() { cancel(owner: ObjectIdentifier(self)) }

  /// Exercises the actual reply form without a provider call or runtime bypass.
  func showDebugPreview() {
    let data = try! JSONSerialization.data(withJSONObject: [
      "type": "agent_question", "id": "debug-question", "runId": "debug-question-run",
      "conversationId": "debug-preview", "agent": "Preview",
      "questions": [
        ["id": "project", "header": "Project", "question": "Which project should I update?", "options": [
          ["label": "Mac app", "description": "Update the native macOS app"],
          ["label": "Website", "description": "Update the marketing website"],
        ]],
        ["id": "detail", "header": "Details", "question": "What would you like to change?"],
      ],
    ])
    _ = handle(data, owner: ObjectIdentifier(self)) { [weak self] response in
      guard let self, let resolved = try? JSONSerialization.data(withJSONObject: [
        "type": "agent_question_resolved", "id": response.requestId, "runId": response.runId,
      ]) else { return }
      _ = self.handle(resolved, owner: ObjectIdentifier(self)) { _ in }
      AppCoordinator.shared?.showNotchDebugScenario(.completed)
    }
  }
}
#endif
