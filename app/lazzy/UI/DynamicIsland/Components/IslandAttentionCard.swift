import SwiftUI

struct IslandAttentionCard: View {
  let run: DetachedAgentRun?
  let question: AgentQuestionEnvelope?
  @ObservedObject var questions: AgentQuestionCenter
  let onApprovalResponse: (String, Bool) -> Void
  @ObservedObject private var theme = ThemeManager.shared

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      HStack(spacing: 8) {
        ProviderLogo(agent: question?.agent ?? run?.agent ?? "", size: 14)
        VStack(alignment: .leading, spacing: 4) {
          Text(run?.taskTitle ?? question?.taskTitle ?? "Agent question")
            .font(.system(size: 13, weight: .medium)).foregroundStyle(theme.textColor).lineLimit(1)
          Text(question != nil ? "Needs your answer" : run?.stateLabel ?? "Needs you")
            .font(.system(size: 11)).foregroundStyle(theme.secondaryTextColor)
        }.frame(maxWidth: .infinity, alignment: .leading)
      }

      if question != nil {
        AgentQuestionForm(center: questions, showsContext: false, requestID: question?.id)
      } else if let approval = run?.approval {
        ScrollView {
          VStack(alignment: .leading, spacing: 9) {
            Text(approval.description.isEmpty ? "Allow this action?" : approval.description)
              .font(.system(size: 12)).foregroundStyle(theme.textColor.opacity(0.8))
              .frame(maxWidth: .infinity, alignment: .leading)
            Text(approval.command)
              .font(.system(size: 10, design: .monospaced)).foregroundStyle(theme.secondaryTextColor)
              .textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading)
              .padding(9).background(theme.controlBackgroundColor, in: RoundedRectangle(cornerRadius: 7))
          }
        }.scrollIndicators(.hidden)
        HStack {
          if approval.riskLevel == "high" {
            Label("High-risk action", systemImage: "exclamationmark.triangle")
              .font(.system(size: 10)).foregroundStyle(theme.secondaryTextColor)
          }
          Spacer(minLength: 0)
          decision("Deny", primary: false) { onApprovalResponse(approval.id, false) }
          decision("Approve", primary: true) { onApprovalResponse(approval.id, true) }
        }
      } else if let credential = run?.credential {
        Label("Use \(credential.label) for \(credential.origin)", systemImage: "touchid")
          .font(.system(size: 12)).foregroundStyle(theme.textColor.opacity(0.8)).lineLimit(2)
        Text("Confirm in the secure Touch ID prompt. Your credential stays hidden.")
          .font(.system(size: 11)).foregroundStyle(theme.secondaryTextColor)
      }
    }
    .padding(12)
    .background(theme.controlBackgroundColor, in: RoundedRectangle(cornerRadius: 12))
    .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(theme.textColor.opacity(0.1), lineWidth: 0.5))
    .padding(.bottom, 8)
  }

  private func decision(_ title: String, primary: Bool, action: @escaping () -> Void) -> some View {
    Button(action: action) {
      Text(title).font(.system(size: 11, weight: .medium))
        .foregroundStyle(primary ? theme.backgroundColor : theme.textColor)
        .padding(.horizontal, 12).padding(.vertical, 7)
        .background(primary ? theme.textColor : theme.textColor.opacity(0.1), in: Capsule())
    }.buttonStyle(.plain)
  }
}
