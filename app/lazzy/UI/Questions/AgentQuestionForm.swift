import SwiftUI

struct AgentQuestionForm: View {
  @ObservedObject var center: AgentQuestionCenter
  @ObservedObject private var theme = ThemeManager.shared
  var showsContext = true
  var requestID: String? = nil
  var compact = false
  var keyboardIsActive: () -> Bool = { true }
  var onCompactHeightChange: ((CGFloat) -> Void)? = nil
  private static let maximumCompactBodyHeight: CGFloat = 176
  @State private var compactBodyHeight = AgentQuestionForm.maximumCompactBodyHeight

  private var request: AgentQuestionEnvelope? {
    if let requestID { return center.requests.first { $0.id == requestID } }
    return center.current
  }

  var body: some View {
    Group {
      if let request {
        questionContent(request)
      }
    }.tint(theme.textColor)
  }

  private func questionContent(_ request: AgentQuestionEnvelope) -> some View {
    let index = center.page(for: request)
    let question = request.questions[index]
    let value = center.answer(for: question, in: request)
    let busy = center.submitting.contains(request.id)
    return VStack(alignment: .leading, spacing: compact ? 8 : 12) {
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
        VStack(alignment: .leading, spacing: compact ? 7 : 10) {
          if request.questions.count > 1 {
            Text("\(index + 1) of \(request.questions.count) · \(question.header)")
              .font(.system(size: 10)).foregroundStyle(theme.textColor.opacity(0.55))
          }
          Text(question.question).font(.system(size: compact ? 12 : 13, weight: .medium)).foregroundStyle(theme.textColor)
            .fixedSize(horizontal: false, vertical: true)
          if question.isSecret != true {
            ForEach(Array((question.options ?? []).enumerated()), id: \.offset) { optionIndex, option in
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
                  if optionIndex < 9 {
                    Text("\(optionIndex + 1)").font(.system(size: 10, design: .monospaced))
                      .foregroundStyle(theme.secondaryTextColor).accessibilityHidden(true)
                  }
                }.foregroundStyle(theme.textColor).padding(compact ? 8 : 10).frame(maxWidth: .infinity, alignment: .leading)
                  .background(theme.textColor.opacity(value == option.label ? 0.12 : 0.035), in: RoundedRectangle(cornerRadius: 6))
              }.buttonStyle(.plain).accessibilityValue(value == option.label ? "Selected" : "Not selected")
                .help(optionIndex < 9 ? "Press \(optionIndex + 1) to select" : option.label)
            }
          }
          answerField(question, request: request)
          if let error = center.errors[request.id] {
            Text(error).font(.system(size: 11)).foregroundStyle(theme.textColor.opacity(0.7))
          }
        }
        .fixedSize(horizontal: false, vertical: true)
        .background {
          if compact {
            GeometryReader { proxy in
              Color.clear.preference(key: QuestionBodyHeightKey.self, value: proxy.size.height)
            }
          }
        }
      }
      .frame(height: compact ? min(compactBodyHeight, Self.maximumCompactBodyHeight) : nil)
      .scrollIndicators(.automatic).disabled(busy)
      .onPreferenceChange(QuestionBodyHeightKey.self) { height in
        guard compact, height > 0 else { return }
        let height = ceil(height)
        if abs(compactBodyHeight - height) > 0.5 { compactBodyHeight = height }
      }
      HStack(spacing: 12) {
        Button(compact ? "Cancel" : "Cancel task") { center.submit(request, cancelled: true) }.foregroundStyle(theme.textColor.opacity(0.6))
        Spacer()
        if index > 0 { Button("Back") { center.setPage(index - 1, for: request) }.foregroundStyle(theme.textColor.opacity(0.8)) }
        Button {
          continueAnswer(request, at: index)
        } label: {
          Text(busy ? "Sending…" : index + 1 < request.questions.count ? "Next" : "Continue")
            .font(.system(size: 12, weight: .semibold)).foregroundStyle(theme.backgroundColor)
            .padding(.horizontal, 14).padding(.vertical, 8)
            .background(theme.textColor.opacity(value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? 0.4 : 1), in: Capsule())
        }.disabled(value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || busy)
      }.font(.system(size: 11)).buttonStyle(.plain).disabled(busy)
    }.padding(.top, compact ? 2 : 12).padding(.bottom, compact ? 10 : 12)
      .background {
        if compact {
          GeometryReader { proxy in
            Color.clear.preference(key: QuestionFormHeightKey.self, value: proxy.size.height)
          }
        }
      }
      .onPreferenceChange(QuestionFormHeightKey.self) { height in
        if compact, height > 0 { onCompactHeightChange?(ceil(height)) }
      }
      .background {
        AgentQuestionKeyboard(enabled: !busy, optionCount: question.isSecret == true ? 0 : question.options?.count ?? 0,
          canContinue: !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
          isActive: {
            keyboardIsActive() && center.page(for: request) == index
              && center.requests.contains(where: { $0.id == request.id }) && !center.submitting.contains(request.id)
          },
          onSelect: { index in
            guard let options = question.options, options.indices.contains(index) else { return }
            center.setAnswer(options[index].label, questionID: question.id, requestID: request.id)
          }, onContinue: { continueAnswer(request, at: index) })
          .allowsHitTesting(false).accessibilityHidden(true)
      }
  }

  private func continueAnswer(_ request: AgentQuestionEnvelope, at index: Int) {
    if index + 1 < request.questions.count { center.setPage(index + 1, for: request) }
    else { center.submit(request) }
  }

  private func answerField(_ question: AgentQuestion, request: AgentQuestionEnvelope) -> some View {
    let binding = Binding(
      get: {
        let answer = center.answer(for: question, in: request)
        // A selected option already carries the answer; keep the optional custom field quiet.
        return compact && question.options?.contains(where: { $0.label == answer }) == true ? "" : answer
      },
      set: { center.setAnswer($0, questionID: question.id, requestID: request.id) }
    )
    return Group {
      if question.isSecret == true { SecureField("Your answer", text: binding) }
      else {
        TextField(question.options?.isEmpty == false ? "Or type a custom answer" : "Your answer",
          text: binding, axis: .vertical).lineLimit(compact ? 1...3 : 2...4)
      }
    }.textFieldStyle(.plain).font(.system(size: 12)).foregroundStyle(theme.textColor).padding(compact ? 8 : 10)
      .background(theme.textColor.opacity(0.07), in: RoundedRectangle(cornerRadius: 8))
      .accessibilityLabel("Answer to \(question.header)")
  }
}

private struct QuestionBodyHeightKey: PreferenceKey {
  static let defaultValue: CGFloat = 0
  static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = max(value, nextValue()) }
}

private struct QuestionFormHeightKey: PreferenceKey {
  static let defaultValue: CGFloat = 0
  static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = max(value, nextValue()) }
}
