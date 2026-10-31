import SwiftUI

/// One stable component per task, from live activity to an inline decision and back.
struct IslandTaskRow: View {
  let run: DetachedAgentRun
  let canStop: Bool
  let canResume: Bool
  let question: AgentQuestionEnvelope?
  @ObservedObject var questions: AgentQuestionCenter
  @ObservedObject var interaction: ActivityIslandTaskState
  @FocusState.Binding var focusedRunID: String?
  let onOpen: () -> Void
  let onSelect: () -> Void
  let onStop: () -> Void
  let onResume: () -> Void
  let onMoveFocus: (Int) -> Void
  let onApprovalResponse: (String, Bool) -> Void
  @State private var isHovered = false
  @ObservedObject private var theme = ThemeManager.shared

  private var isExpanded: Bool { interaction.expandedRunID == run.id }
  private var showsControls: Bool { isHovered || focusedRunID == run.id }

  var body: some View {
    VStack(spacing: 0) {
      Button(action: run.needsAttention ? onSelect : onOpen) {
        HStack(alignment: .top, spacing: 10) {
          ProviderLogo(agent: run.agent, size: 16).frame(width: 20).padding(.top, 2)
          VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 5) {
              Text(run.taskTitle).font(.system(size: 13, weight: .medium)).lineLimit(1)
              if run.isUnread {
                Circle().fill(theme.textColor).frame(width: 4, height: 4).accessibilityLabel("Unread result")
              }
            }
            if !isExpanded {
              IslandTaskStatus(run: run, questionSummary: question.map { $0.questions[questions.page(for: $0)].question })
            }
            metadata
          }.frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.trailing, 54)
        .frame(maxWidth: .infinity,
          minHeight: isExpanded ? ActivityIslandContentLayout.expandedRowHeight : ActivityIslandContentLayout.rowHeight,
          maxHeight: isExpanded ? ActivityIslandContentLayout.expandedRowHeight : ActivityIslandContentLayout.rowHeight, alignment: .center)
        .contentShape(Rectangle())
      }
      .buttonStyle(.plain)
      .focused($focusedRunID, equals: run.id)
      .onKeyPress(.downArrow) { onMoveFocus(1); return .handled }
      .onKeyPress(.upArrow) { onMoveFocus(-1); return .handled }
      .onKeyPress(.return) {
        if isExpanded && run.state == .awaitingInput { return .ignored }
        activate(); return .handled
      }
      .help(run.needsAttention ? "Expand or collapse this request" : "Open conversation")
      .accessibilityLabel("\(run.taskTitle), \(ProviderIdentity(run.agent).name), \(run.projectLabel), \(run.stateLabel), \(run.currentActivity)")
      .accessibilityValue(run.needsAttention ? (isExpanded ? "Expanded" : "Collapsed") : run.stateLabel)
      .overlay(alignment: .trailing) { actions }

      if isExpanded {
        IslandTaskInteraction(run: run, question: question, questions: questions, interaction: interaction,
          onApprovalResponse: onApprovalResponse)
          .transition(.opacity.combined(with: .move(edge: .top)))
      }
    }
    .padding(.horizontal, 8)
    .background(theme.textColor.opacity(isExpanded ? 0.055 : showsControls ? 0.035 : 0),
      in: RoundedRectangle(cornerRadius: 9, style: .continuous))
    .clipped()
    .onHover { isHovered = $0 }
  }

  private func activate() { if run.needsAttention { onSelect() } else { onOpen() } }

  private var metadata: some View {
    HStack(spacing: 4) {
      Text(ProviderIdentity(run.agent).name).fixedSize()
      if run.workspacePath != nil {
        Text("·").accessibilityHidden(true)
        Text(run.projectLabel).truncationMode(.middle).help(run.workspacePath ?? "")
      }
      Text("·").accessibilityHidden(true)
      TimelineView(.periodic(from: .now, by: 30)) { context in
        Text(elapsed(at: run.isActive ? context.date : run.updatedAt)).monospacedDigit()
          .help("Elapsed time").fixedSize()
      }
    }
    .font(.system(size: 10)).foregroundStyle(theme.secondaryTextColor.opacity(0.8)).lineLimit(1)
  }

  private func elapsed(at date: Date) -> String {
    let minutes = max(0, Int(date.timeIntervalSince(run.startedAt) / 60))
    if minutes == 0 { return "<1m" }
    return minutes < 60 ? "\(minutes)m" : "\(minutes / 60)h \(minutes % 60)m"
  }

  private var actions: some View {
    HStack(spacing: 2) {
      if run.isActive {
        IslandActionButton(symbol: "stop.fill", title: "Stop task", enabled: canStop, action: onStop)
      } else if run.state == .stopped || run.state == .failed {
        IslandActionButton(symbol: "play.fill", title: "Resume task", enabled: canResume, action: onResume)
      }
      IslandActionButton(symbol: "arrow.up.right", title: "Open conversation",
        enabled: run.conversationId != nil, action: onOpen)
    }
    .opacity(showsControls ? 1 : 0).allowsHitTesting(showsControls)
    .disabled(!showsControls).accessibilityHidden(!showsControls)
  }
}

private struct IslandTaskStatus: View {
  let run: DetachedAgentRun
  let questionSummary: String?
  @ObservedObject private var theme = ThemeManager.shared

  var body: some View {
    HStack(spacing: 5) {
      if run.state == .running || run.state == .stopping {
        ProgressView().controlSize(.mini).scaleEffect(0.65).frame(width: 9, height: 9)
          .accessibilityHidden(true)
      } else {
        Image(systemName: symbol).font(.system(size: 9, weight: .medium)).frame(width: 9)
      }
      Text(activity).lineLimit(1).truncationMode(.tail)
      if let progress = run.progress {
        Text(progress.label).font(.system(size: 10)).monospacedDigit().fixedSize()
          .accessibilityLabel("\(progress.completed) of \(progress.total) reported plan steps complete")
      }
    }.font(.system(size: 11)).foregroundStyle(theme.secondaryTextColor)
  }

  private var activity: String {
    if let questionSummary, run.state == .awaitingInput { return questionSummary }
    if run.state == .failed || run.state == .completed { return "\(run.stateLabel) · \(run.currentActivity)" }
    if run.state == .stopped { return run.stateLabel }
    return run.currentActivity
  }

  private var symbol: String {
    switch run.state {
    case .awaitingApproval: return "hand.raised"
    case .awaitingInput: return "questionmark.bubble"
    case .awaitingCredential: return "touchid"
    case .completed: return "checkmark"
    case .failed: return "exclamationmark.circle"
    case .stopped: return "stop.circle"
    case .running, .stopping: return "circle"
    }
  }
}

struct IslandActionButton: View {
  let symbol: String
  let title: String
  var enabled = true
  let action: () -> Void
  @State private var isHovered = false
  @ObservedObject private var theme = ThemeManager.shared

  var body: some View {
    Button(action: action) {
      Image(systemName: symbol).font(.system(size: 10, weight: .medium))
        .foregroundStyle(theme.textColor.opacity(enabled ? 0.8 : 0.2))
        .frame(width: 25, height: 26)
        .background(theme.textColor.opacity(isHovered && enabled ? 0.1 : 0), in: RoundedRectangle(cornerRadius: 5))
        .contentShape(Rectangle())
    }
    .buttonStyle(.plain).disabled(!enabled)
    .help(title).accessibilityLabel(title)
    .onHover { isHovered = $0 }
  }
}
