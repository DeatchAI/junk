import SwiftUI

struct IslandTaskRow: View {
  let run: DetachedAgentRun
  let canStop: Bool
  let canResume: Bool
  let isSelected: Bool
  let onOpen: () -> Void
  let onSelect: () -> Void
  let onStop: () -> Void
  let onResume: () -> Void
  @State private var isHovered = false
  @ObservedObject private var theme = ThemeManager.shared

  var body: some View {
    HStack(spacing: 10) {
      Button(action: run.needsAttention ? onSelect : onOpen) {
        HStack(spacing: 10) {
          ProviderLogo(agent: run.agent, size: 16)
            .frame(width: 20)
          VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 5) {
              if run.isUnread { Circle().fill(theme.textColor).frame(width: 5, height: 5).accessibilityLabel("Unread result") }
              Text(run.taskTitle)
                .font(.system(size: 13, weight: .medium)).foregroundStyle(theme.textColor)
                .lineLimit(1).truncationMode(.tail)
            }
            HStack(spacing: 5) {
              Text(ProviderIdentity(run.agent).name).fixedSize()
              Text("·").accessibilityHidden(true)
              Text(run.projectLabel).truncationMode(.middle)
                .help(run.workspacePath ?? "No project selected")
            }
            .font(.system(size: 11, weight: .regular))
            .foregroundStyle(theme.secondaryTextColor)
            .lineLimit(1)
            IslandRunState(run: run).font(.system(size: 11)).foregroundStyle(theme.secondaryTextColor)
          }
          .frame(maxWidth: .infinity, alignment: .leading)
        }
        .contentShape(Rectangle())
      }
      .buttonStyle(.plain)
      .help("\(run.needsAttention ? "Review what this task needs" : "Open conversation") · \(run.currentActivity)")
      .accessibilityLabel("\(run.taskTitle), \(ProviderIdentity(run.agent).name), \(run.projectLabel), \(run.stateLabel), \(run.currentActivity)")

      HStack(spacing: 5) {
        if run.isActive {
          IslandActionButton(symbol: "stop.fill", title: run.state == .stopping ? "Stopping task" : "Stop task",
            enabled: canStop, action: onStop)
        } else if run.state == .stopped || run.state == .failed {
          IslandActionButton(symbol: "play.fill", title: "Resume in this conversation",
            enabled: canResume, action: onResume)
        }
        if run.state == .completed {
          Button("Open result", action: onOpen)
            .font(.system(size: 11, weight: .medium)).buttonStyle(.plain)
            .foregroundStyle(theme.textColor).padding(.horizontal, 9).padding(.vertical, 7)
            .background(theme.textColor.opacity(0.08), in: Capsule())
            .disabled(run.conversationId == nil)
        } else {
          IslandActionButton(symbol: "arrow.up.right", title: "Open conversation",
            enabled: run.conversationId != nil, action: onOpen)
        }
      }
    }
    .padding(.horizontal, 8)
    .frame(height: ActivityIslandContentLayout.rowHeight)
    .background(theme.textColor.opacity(isSelected ? 0.09 : isHovered ? 0.045 : 0),
      in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    .onHover { isHovered = $0 }
  }
}

private struct IslandRunState: View {
  let run: DetachedAgentRun
  @ObservedObject private var theme = ThemeManager.shared

  var body: some View {
    HStack(spacing: 4) {
      if run.state == .running || run.state == .stopping {
        ProgressView().controlSize(.mini).scaleEffect(0.65).frame(width: 9, height: 9).tint(theme.textColor)
      } else {
        Image(systemName: symbol).font(.system(size: 9, weight: .medium))
      }
      Text(run.state == .running || run.state == .completed ? run.currentActivity : run.stateLabel)
        .lineLimit(1).truncationMode(.tail)
    }
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
      Image(systemName: symbol).font(.system(size: 10, weight: .semibold))
        .foregroundStyle(theme.textColor.opacity(enabled ? 0.85 : 0.2))
        .frame(width: 26, height: 26)
        .background(theme.textColor.opacity(isHovered && enabled ? 0.16 : 0.065), in: Circle())
        .contentShape(Circle())
    }
    .buttonStyle(.plain).disabled(!enabled)
    .help(title).accessibilityLabel(title)
    .onHover { isHovered = $0 }
  }
}
