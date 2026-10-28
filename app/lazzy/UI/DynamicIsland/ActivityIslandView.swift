import SwiftUI

/// Quiet when collapsed; a task switcher and decision surface on hover.
struct ActivityIslandView: View {
  @ObservedObject private var theme = ThemeManager.shared
  @ObservedObject private var questions = AgentQuestionCenter.shared
  @ObservedObject var store: DetachedRunStore
  @ObservedObject var controller: ActivityIslandWindowController
  @ObservedObject var controls: DetachedRunControls
  let onToggle: () -> Void
  let onOpenConversation: (String) -> Void
  let onApprovalResponse: (String, Bool) -> Void

  private var activeRuns: [DetachedAgentRun] { store.visibleActiveRuns }
  private var needsAttention: Bool { activeRuns.contains(where: \.needsAttention) }

  var body: some View {
    VStack(spacing: 0) {
      if controller.isExpanded {
        if !controller.placement.isSide {
          Color.clear.frame(height: controller.physicalNotchHeight)
        }
        ActivityIslandTaskList(store: store, controls: controls, questions: questions,
          onOpenConversation: onOpenConversation, onApprovalResponse: onApprovalResponse)
          .padding(.horizontal, controller.placement.isSide
            ? ActivityIslandContentLayout.sideInset : ActivityIslandContentLayout.topInset)
          .padding(.vertical, controller.placement.isSide ? ActivityIslandContentLayout.sideInset : 0)
      } else {
        compactHeadline
      }
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    .foregroundStyle(theme.textColor)
    .themedSurface(in: ScreenEdgeNotchShape(placement: controller.placement))
    .preferredColorScheme(theme.surfaceColorScheme)
    .tint(theme.textColor)
    .animation(.easeInOut(duration: 0.28), value: controller.isExpanded)
    .onHover { controller.setHovering($0) }
  }

  private var compactHeadline: some View {
    Button(action: onToggle) {
      Group {
        if controller.placement.isSide {
          VStack(spacing: 10) {
            compactMark
            compactCountBadge
          }.frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
          HStack {
            compactMark
            Spacer(minLength: 0)
            compactCountBadge
          }
          .padding(.horizontal, 20)
          .frame(height: controller.physicalNotchHeight + ActivityIslandLayout.compactHeightPadding)
        }
      }.contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .help(needsAttention ? "An agent needs your attention" : store.hasUnreadResults ? "\(store.unreadRuns.count) results ready to review" : "Show detached tasks")
    .accessibilityLabel(needsAttention ? "Show tasks needing your attention" : "Show detached tasks")
  }

  @ViewBuilder private var compactMark: some View {
    if let run = store.primaryRun {
      ProviderLogo(agent: run.agent, size: controller.placement.isSide ? 18 : 20)
    } else {
      Image("DetachedMark").renderingMode(.template).resizable().scaledToFit().frame(width: 18, height: 18)
    }
  }

  private var compactCountBadge: some View {
    Group {
      if needsAttention {
        Image(systemName: "questionmark").font(.system(size: 10, weight: .bold))
      } else if activeRuns.isEmpty && store.hasUnreadResults {
        Text("\(store.unreadRuns.count)").font(.appFont(size: 10, weight: .semibold)).monospacedDigit()
      } else if !activeRuns.isEmpty {
        Text("\(activeRuns.count)").font(.appFont(size: 10, weight: .semibold)).monospacedDigit()
      } else {
        Image(systemName: store.primaryRun?.state == .completed ? "checkmark" :
          store.primaryRun?.state == .stopped ? "stop.fill" : "exclamationmark")
          .font(.system(size: 9, weight: .bold))
      }
    }
    .foregroundStyle(theme.backgroundColor).frame(minWidth: 18, minHeight: 18, maxHeight: 18)
    .padding(.horizontal, 1).background(theme.textColor, in: Capsule())
    .accessibilityLabel(needsAttention ? "Needs your attention" :
      activeRuns.isEmpty ? (store.hasUnreadResults ? "\(store.unreadRuns.count) unread results" : store.primaryRun?.stateLabel ?? "No active tasks") : "\(activeRuns.count) active tasks")
  }
}
