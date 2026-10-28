import SwiftUI

struct AgentQuestionForm: View {
  @ObservedObject var center: AgentQuestionCenter
  @ObservedObject private var theme = ThemeManager.shared
  var showsContext = true
  var requestID: String? = nil
  @State private var page = 0

  private var request: AgentQuestionEnvelope? {
    if let requestID { return center.requests.first { $0.id == requestID } }
    return center.current
  }

  var body: some View {
    Group {
      if let request {
        questionContent(request).onChange(of: request.id) { _, _ in page = 0 }
      }
    }.tint(theme.textColor)
  }

  private func questionContent(_ request: AgentQuestionEnvelope) -> some View {
    let index = min(page, request.questions.count - 1)
    let question = request.questions[index]
    let value = center.answer(for: question, in: request)
    let busy = center.submitting.contains(request.id)
    return VStack(alignment: .leading, spacing: 12) {
      if showsContext { HStack {
        Image(systemName: "questionmark.bubble.fill")
        Text("\(request.agent.capitalized) needs your answer").font(.system(size: 12, weight: .semibold))
        Spacer(minLength: 0)
        if center.requests.count > 1 {
          Text("+\(center.requests.count - 1)").font(.system(size: 11)).foregroundStyle(theme.textColor.opacity(0.6))
        }
      }.foregroundStyle(theme.textColor)
      }
      if showsContext, let title = request.taskTitle, !title.isEmpty {
        Text(title).font(.system(size: 10)).foregroundStyle(theme.textColor.opacity(0.55)).lineLimit(1)
      }
      ScrollView {
        VStack(alignment: .leading, spacing: 10) {
          if request.questions.count > 1 {
            Text("\(index + 1) of \(request.questions.count) · \(question.header)")
              .font(.system(size: 10)).foregroundStyle(theme.textColor.opacity(0.55))
          }
          Text(question.question).font(.system(size: 13, weight: .medium)).foregroundStyle(theme.textColor)
            .fixedSize(horizontal: false, vertical: true)
          if question.isSecret != true {
            ForEach(Array((question.options ?? []).enumerated()), id: \.offset) { _, option in
              Button { center.setAnswer(option.label, questionID: question.id, requestID: request.id) } label: {
                HStack(alignment: .top, spacing: 8) {
                  Image(systemName: value == option.label ? "checkmark.circle.fill" : "circle")
                  VStack(alignment: .leading, spacing: 3) {
                    Text(option.label).font(.system(size: 12, weight: .medium))
                    if let description = option.description, !description.isEmpty {
                      Text(description).font(.system(size: 10)).foregroundStyle(theme.textColor.opacity(0.6))
                    }
                  }
                  Spacer(minLength: 0)
                }.foregroundStyle(theme.textColor).padding(10).frame(maxWidth: .infinity, alignment: .leading)
                  .background(theme.textColor.opacity(value == option.label ? 0.16 : 0.06), in: RoundedRectangle(cornerRadius: 8))
              }.buttonStyle(.plain)
            }
          }
          answerField(question, request: request)
          if let error = center.errors[request.id] {
            Text(error).font(.system(size: 11)).foregroundStyle(theme.textColor.opacity(0.7))
          }
        }
      }.scrollIndicators(.hidden).disabled(busy)
      HStack(spacing: 12) {
        Button("Cancel task") { center.submit(request, cancelled: true) }.foregroundStyle(theme.textColor.opacity(0.6))
        Spacer()
        if index > 0 { Button("Back") { page = index - 1 }.foregroundStyle(theme.textColor.opacity(0.8)) }
        Button {
          if index + 1 < request.questions.count { page = index + 1 }
          else { center.submit(request) }
        } label: {
          Text(busy ? "Sending…" : index + 1 < request.questions.count ? "Next" : "Continue")
            .font(.system(size: 12, weight: .semibold)).foregroundStyle(theme.backgroundColor)
            .padding(.horizontal, 14).padding(.vertical, 8)
            .background(theme.textColor.opacity(value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? 0.4 : 1), in: Capsule())
        }.disabled(value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || busy)
      }.font(.system(size: 11)).buttonStyle(.plain).disabled(busy)
    }.padding(.vertical, 12)
  }

  private func answerField(_ question: AgentQuestion, request: AgentQuestionEnvelope) -> some View {
    let binding = Binding(
      get: { center.answer(for: question, in: request) },
      set: { center.setAnswer($0, questionID: question.id, requestID: request.id) }
    )
    return Group {
      if question.isSecret == true { SecureField("Your answer", text: binding) }
      else {
        TextField(question.options?.isEmpty == false ? "Choose above or type your answer" : "Your answer",
          text: binding, axis: .vertical).lineLimit(2...4)
      }
    }.textFieldStyle(.plain).font(.system(size: 12)).foregroundStyle(theme.textColor).padding(10)
      .background(theme.textColor.opacity(0.07), in: RoundedRectangle(cornerRadius: 8))
      .accessibilityLabel("Answer to \(question.header)")
  }
}
