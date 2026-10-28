import SwiftUI

struct AgentContextDetailView: View {
  let summary: ChatContextSummary?
  @ObservedObject private var theme = ThemeManager.shared

  var body: some View {
    VStack(alignment: .leading, spacing: 10) {
      Text("Last message context")
        .font(.appFont(size: 12, weight: .medium))
        .foregroundColor(theme.textColor)
      if let summary {
        estimateRow("Your message", characters: summary.userCharacters)
        estimateRow("Selected instructions", characters: summary.instructionCharacters)
        estimateRow("Attached text and paths", characters: summary.attachmentCharacters)
        detailRow("Files", value: "\(summary.fileCount)")
        detailRow("Tool connections", value: "\(summary.toolServerCount)")
        Text("Estimates use 4 characters per token. Native agent instructions, history, tool schemas and file contents are excluded; their token counts are unavailable here.")
          .font(.appFont(size: 11))
          .foregroundColor(theme.secondaryTextColor)
          .fixedSize(horizontal: false, vertical: true)
      } else {
        Text("Send a message to see what Detach adds to it.")
          .font(.appFont(size: 12))
          .foregroundColor(theme.secondaryTextColor)
      }
    }
    .padding(12)
    .frame(width: 292, alignment: .leading)
    .themedSurface(in: RoundedRectangle(cornerRadius: 12, style: .continuous))
  }

  private func estimateRow(_ title: String, characters: Int) -> some View {
    detailRow(title, value: characters == 0 ? "0 tokens" : "≈\((characters + 3) / 4) tokens")
  }

  private func detailRow(_ title: String, value: String) -> some View {
    HStack {
      Text(title)
      Spacer()
      Text(value).monospacedDigit()
    }
    .font(.appFont(size: 11))
    .foregroundColor(theme.secondaryTextColor)
  }
}

struct AgentPermissionChoicesView: View {
  let agentID: String
  let selected: AgentPermissionMode
  let onSelect: (AgentPermissionMode) -> Void
  @ObservedObject private var theme = ThemeManager.shared

  var body: some View {
    VStack(alignment: .leading, spacing: 2) {
      ForEach(AgentPermissionMode.allCases) { mode in
        Button { onSelect(mode) } label: {
          HStack {
            Text(mode.title(for: agentID))
            Spacer(minLength: 8)
            if mode == selected { Image(systemName: "checkmark").font(.appFont(size: 10)) }
          }
          .font(.appFont(size: 12))
          .foregroundColor(theme.textColor)
          .padding(.horizontal, 10)
          .padding(.vertical, 8)
          .contentShape(Rectangle())
        }
        .buttonStyle(ComposerButtonStyle())
      }
    }
    .padding(6)
    .frame(width: 210)
    .themedSurface(in: RoundedRectangle(cornerRadius: 12, style: .continuous))
  }
}
