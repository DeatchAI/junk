import SwiftUI

/// The body of a task row. Identity, title, provider, and status belong to its header.
struct IslandTaskInteraction: View {
  let run: DetachedAgentRun
  let question: AgentQuestionEnvelope?
  @ObservedObject var questions: AgentQuestionCenter
  @ObservedObject var interaction: ActivityIslandTaskState
  let onApprovalResponse: (String, Bool) -> Void
  @ObservedObject private var theme = ThemeManager.shared

  var body: some View {
    Group {
      if let question {
        AgentQuestionForm(center: questions, showsContext: false, requestID: question.id, compact: true,
          keyboardIsActive: { interaction.expandedRunID == run.id },
          onCompactHeightChange: { interaction.reportHeight($0, for: run.id) })
      } else if let approval = run.approval {
        approvalContent(approval).frame(height: ActivityIslandContentLayout.approvalHeight)
      } else if let credential = run.credential {
        VStack(alignment: .leading, spacing: 6) {
          Text("Use \(credential.label) for \(credential.origin)")
            .font(.system(size: 12)).fixedSize(horizontal: false, vertical: true)
          Text("Confirm in the secure Touch ID prompt. Your credential stays hidden.")
            .font(.system(size: 11)).foregroundStyle(theme.secondaryTextColor)
        }.frame(height: ActivityIslandContentLayout.credentialHeight, alignment: .top)
      } else {
        Text("Waiting for the agent’s request…")
          .font(.system(size: 11)).foregroundStyle(theme.secondaryTextColor).padding(.vertical, 12)
      }
    }
    .padding(.leading, 30).padding(.trailing, 8)
  }

  private func approvalContent(_ approval: DetachedRunApproval) -> some View {
    let busy = interaction.submittingApprovals.contains(approval.id)
    return VStack(alignment: .leading, spacing: 10) {
      ScrollView {
        VStack(alignment: .leading, spacing: 8) {
          if !approval.description.isEmpty {
            Text(approval.description).font(.system(size: 12))
              .fixedSize(horizontal: false, vertical: true)
          }
          Text(approval.command)
            .font(.system(size: 11, design: .monospaced))
            .textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(9).background(theme.textColor.opacity(0.055), in: RoundedRectangle(cornerRadius: 6))
            .accessibilityLabel("Exact command: \(approval.command)")
        }.frame(maxWidth: .infinity, alignment: .leading)
      }.scrollIndicators(.automatic)
      HStack(spacing: 8) {
        if !approval.riskLevel.isEmpty {
          Label("\(approval.riskLevel.capitalized) risk", systemImage: "exclamationmark.shield")
            .font(.system(size: 10)).foregroundStyle(theme.secondaryTextColor)
            .lineLimit(1)
        }
        Spacer(minLength: 0)
        decision("Deny", primary: false) { respond(approval, approved: false) }
        decision(busy ? "Sending…" : "Approve", primary: true) { respond(approval, approved: true) }
      }.disabled(busy)
    }.padding(.top, 2).padding(.bottom, 10)
  }

  private func respond(_ approval: DetachedRunApproval, approved: Bool) {
    interaction.respond(to: approval, approved: approved, send: onApprovalResponse)
  }

  private func decision(_ title: String, primary: Bool, action: @escaping () -> Void) -> some View {
    Button(action: action) {
      Text(title).font(.system(size: 11, weight: .medium))
        .foregroundStyle(primary ? theme.backgroundColor : theme.textColor)
        .padding(.horizontal, 12).padding(.vertical, 7)
        .background(primary ? theme.textColor : theme.textColor.opacity(0.08), in: Capsule())
    }.buttonStyle(.plain)
  }
}
