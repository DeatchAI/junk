import SwiftUI

struct ComposerQuestionView: View {
  let request: AgentQuestionEnvelope
  @ObservedObject var center: AgentQuestionCenter
  @ObservedObject var controller: FloatingWindowController
  let onClose: () -> Void
  @ObservedObject private var theme = ThemeManager.shared

  private var questionHeight: CGFloat {
    controller.isExpanded ? min(300, max(140, controller.expandedContentHeight - 130)) : 300
  }

  var body: some View {
    VStack(spacing: 0) {
      HStack {
        Label("Reply to \(AgentProvider.displayName(for: request.agent))", systemImage: "questionmark.bubble")
          .font(.appFont(size: 11, weight: .medium)).foregroundStyle(theme.secondaryTextColor)
        Spacer(minLength: 8)
        ComposerWindowControls(controller: controller, onClose: onClose)
      }
      AgentQuestionForm(center: center, showsContext: false, requestID: request.id)
        .id(request.id)
        .frame(height: questionHeight)
    }
    .padding(.horizontal, 18).padding(.top, 14).padding(.bottom, 6)
    .preferredColorScheme(theme.surfaceColorScheme)
  }
}
