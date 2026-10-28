import SwiftUI

struct ActivityIslandTaskList: View {
  @ObservedObject var store: DetachedRunStore
  @ObservedObject var controls: DetachedRunControls
  @ObservedObject var questions: AgentQuestionCenter
  let onOpenConversation: (String) -> Void
  let onApprovalResponse: (String, Bool) -> Void
  @State private var selectedRunID: String?

  private var attentionRun: DetachedAgentRun? {
    store.presentationRuns.first { $0.id == selectedRunID && $0.needsAttention }
      ?? store.presentationRuns.first(where: \.needsAttention)
  }

  private var question: AgentQuestionEnvelope? {
    guard let attentionRun else { return questions.current }
    return attentionRun.state == .awaitingInput
      ? questions.requests.first(where: { $0.runId == attentionRun.id }) : nil
  }

  var body: some View {
    VStack(spacing: 0) {
      if attentionRun != nil || question != nil {
        IslandAttentionCard(run: attentionRun, question: question, questions: questions,
          onApprovalResponse: onApprovalResponse)
          .frame(height: question != nil ? ActivityIslandContentLayout.questionHeight :
            attentionRun?.approval != nil ? ActivityIslandContentLayout.approvalHeight : ActivityIslandContentLayout.credentialHeight)
      }

      ScrollView {
        LazyVStack(spacing: 0) {
          ForEach(store.presentationRuns) { run in
            IslandTaskRow(run: run, canStop: controls.canStop(run), canResume: controls.canResume(run),
              isSelected: attentionRun?.id == run.id,
              onOpen: { if let id = run.conversationId { onOpenConversation(id) } },
              onSelect: { select(run) },
              onStop: { controls.stop(run) }, onResume: { controls.resume(run) })
          }
        }
      }.scrollIndicators(.hidden)
    }
    .padding(.bottom, ActivityIslandContentLayout.bottomInset)
    .onChange(of: question?.id) { _, id in
      if let id, questions.current?.id != id { questions.showQuestion(id) }
    }
  }

  private func select(_ run: DetachedAgentRun) {
    selectedRunID = run.id
    if let question = questions.requests.first(where: { $0.runId == run.id }) {
      questions.showQuestion(question.id)
    }
  }
}
