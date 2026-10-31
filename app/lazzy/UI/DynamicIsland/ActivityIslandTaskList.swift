import SwiftUI

struct ActivityIslandTaskList: View {
  @ObservedObject var store: DetachedRunStore
  @ObservedObject var controls: DetachedRunControls
  @ObservedObject var questions: AgentQuestionCenter
  @ObservedObject var interaction: ActivityIslandTaskState
  let onOpenConversation: (String) -> Void
  let onApprovalResponse: (String, Bool) -> Void
  let onBeginInteraction: () -> Void
  let onDismiss: () -> Void
  @ObservedObject private var theme = ThemeManager.shared
  @FocusState private var focusedRunID: String?
  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  private var runs: [DetachedAgentRun] { ActivityIslandTaskState.ordered(store.presentationRuns) }
  private var animation: Animation? { reduceMotion ? nil : .easeInOut(duration: 0.24) }

  var body: some View {
    VStack(spacing: 0) {
      HStack {
        Text("Activity").font(.system(size: 12, weight: .medium))
        Spacer(minLength: 0)
        let pending = runs.filter(\.needsAttention).count
        if pending > 0 {
          Text("\(pending) pending").font(.system(size: 11)).monospacedDigit()
            .foregroundStyle(theme.secondaryTextColor)
            .accessibilityLabel("\(pending) tasks need your attention")
        }
      }.padding(.horizontal, 8).frame(height: ActivityIslandContentLayout.headerHeight)

      if runs.isEmpty {
        Label("All caught up", systemImage: "checkmark")
          .font(.system(size: 12)).foregroundStyle(theme.secondaryTextColor)
          .frame(maxWidth: .infinity, maxHeight: .infinity)
      } else {
        taskScrollView
      }
    }
    .padding(.top, ActivityIslandContentLayout.contentTopInset)
    .padding(.bottom, ActivityIslandContentLayout.bottomInset)
    .animation(animation, value: interaction.expandedRunID)
    .onExitCommand {
      if interaction.expandedRunID != nil { interaction.collapse() }
      else { onDismiss() }
    }
  }

  private var taskScrollView: some View {
    ScrollViewReader { proxy in
      ScrollView {
        // A single ForEach keeps a task's identity when its section changes.
        LazyVStack(spacing: 0) {
          ForEach(Array(runs.enumerated()), id: \.element.id) { index, run in
            VStack(spacing: 0) {
              if index == 0 || ActivityIslandTaskState.section(for: runs[index - 1]) != ActivityIslandTaskState.section(for: run) {
                sectionHeading(ActivityIslandTaskState.section(for: run), divided: index > 0)
              }
              IslandTaskRow(run: run, canStop: controls.canStop(run), canResume: controls.canResume(run),
                question: questions.requests.first { $0.runId == run.id }, questions: questions,
                interaction: interaction, focusedRunID: $focusedRunID,
                onOpen: { if let id = run.conversationId { onOpenConversation(id) } },
                onSelect: { onBeginInteraction(); focusedRunID = run.id; interaction.toggle(run) },
                onStop: { controls.stop(run) }, onResume: { controls.resume(run) },
                onMoveFocus: { moveFocus(from: run.id, by: $0) },
                onApprovalResponse: onApprovalResponse)
            }.id(run.id)
          }
        }
      }
      .scrollIndicators(.automatic)
      .onChange(of: focusedRunID) { _, id in
        if let id { withAnimation(animation) { proxy.scrollTo(id, anchor: .center) } }
      }
      .onChange(of: interaction.expandedRunID) { previous, id in
        if let id { withAnimation(animation) { proxy.scrollTo(id, anchor: .top) } }
        else if let previous, runs.contains(where: { $0.id == previous }) { focusedRunID = previous }
      }
    }
  }

  private func sectionHeading(_ section: ActivityIslandTaskState.Section, divided: Bool) -> some View {
    VStack(spacing: 0) {
      if divided { theme.textColor.opacity(0.08).frame(height: 0.5) }
      Text(section.title).font(.system(size: 10, weight: .medium)).foregroundStyle(theme.secondaryTextColor)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .padding(.horizontal, 8)
    }.frame(height: ActivityIslandContentLayout.sectionHeight)
  }

  private func moveFocus(from id: String, by offset: Int) {
    guard let index = runs.firstIndex(where: { $0.id == id }) else { return }
    let next = min(max(index + offset, 0), runs.count - 1)
    if runs.indices.contains(next) {
      onBeginInteraction()
      focusedRunID = runs[next].id
    }
  }
}
